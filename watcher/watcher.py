#!/usr/bin/env python3
"""
Nginx Log Watcher for Blue/Green Deployment Monitoring
Monitors failover events and error rates, sends alerts to Slack
"""

import os
import time
import re
from collections import deque
from datetime import datetime
import requests
import json
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class LogWatcher:
    def __init__(self):
        # Configuration from environment variables
        self.slack_webhook_url = os.getenv('SLACK_WEBHOOK_URL', '')
        self.error_rate_threshold = float(os.getenv('ERROR_RATE_THRESHOLD', 2.0))
        self.window_size = int(os.getenv('WINDOW_SIZE', 200))
        self.alert_cooldown_sec = int(os.getenv('ALERT_COOLDOWN_SEC', 300))
        self.maintenance_mode = os.getenv('MAINTENANCE_MODE', 'false').lower() == 'true'
        
        # State tracking
        self.last_seen_pool = None
        self.request_window = deque(maxlen=self.window_size)
        self.last_alert_time = {}
        self.log_file = '/var/log/nginx/access.log'
        
        # Ensure log directory exists
        Path('/var/log/nginx').mkdir(parents=True, exist_ok=True)
        
        logger.info(f"LogWatcher initialized: threshold={self.error_rate_threshold}%, window={self.window_size}, cooldown={self.alert_cooldown_sec}s")

    def parse_log_line(self, line):
        """Parse a custom format nginx log line"""
        try:
            # Parse key=value pairs from custom log format
            pattern = r'(\w+):([^|]+)'
            matches = re.findall(pattern, line)
            log_data = dict(matches)
            
            # Extract relevant fields
            parsed = {
                'timestamp': log_data.get('time', ''),
                'remote_addr': log_data.get('remote_addr', ''),
                'method': log_data.get('method', ''),
                'uri': log_data.get('uri', ''),
                'status': int(log_data.get('status', 0)),
                'request_time': float(log_data.get('request_time', 0)),
                'upstream_addr': log_data.get('upstream_addr', ''),
                'upstream_status': log_data.get('upstream_status', ''),
                'upstream_response_time': log_data.get('upstream_response_time', ''),
                'pool': log_data.get('pool', 'unknown'),
                'release': log_data.get('release', 'unknown')
            }
            
            return parsed
        except Exception as e:
            logger.debug(f"Failed to parse log line: {e}")
            return None

    def calculate_error_rate(self):
        """Calculate 5xx error rate in current window"""
        if not self.request_window:
            return 0.0
        
        error_count = sum(1 for req in self.request_window 
                         if 500 <= req.get('status', 0) < 600)
        
        return (error_count / len(self.request_window)) * 100

    def can_send_alert(self, alert_type):
        """Check if we can send alert (respect cooldown)"""
        now = time.time()
        last_time = self.last_alert_time.get(alert_type, 0)
        
        if now - last_time < self.alert_cooldown_sec:
            logger.info(f"Alert {alert_type} in cooldown, skipping")
            return False
        
        self.last_alert_time[alert_type] = now
        return True

    def send_slack_alert(self, message, alert_type="info"):
        """Send alert to Slack"""
        if not self.slack_webhook_url:
            logger.warning("No SLACK_WEBHOOK_URL configured")
            return False
        
        if self.maintenance_mode:
            logger.info("Maintenance mode active, suppressing alert")
            return False
        
        if not self.can_send_alert(alert_type):
            return False

        # Color coding for different alert types
        colors = {
            "failover": "#FF0000",  # Red
            "error_rate": "#FFA500",  # Orange
            "recovery": "#00FF00",  # Green
            "info": "#4287f5"  # Blue
        }
        
        payload = {
            "attachments": [
                {
                    "color": colors.get(alert_type, "#4287f5"),
                    "title": f"🚨 Blue/Green Deployment Alert - {alert_type.upper().replace('_', ' ')}",
                    "text": message,
                    "fields": [
                        {
                            "title": "Environment",
                            "value": f"Threshold: {self.error_rate_threshold}%, Window: {self.window_size}",
                            "short": True
                        },
                        {
                            "title": "Timestamp",
                            "value": datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC"),
                            "short": True
                        }
                    ],
                    "footer": "Blue/Green Monitor",
                    "ts": time.time()
                }
            ]
        }

        try:
            response = requests.post(
                self.slack_webhook_url,
                data=json.dumps(payload),
                headers={'Content-Type': 'application/json'},
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Slack alert sent: {alert_type}")
                return True
            else:
                logger.error(f"Slack API error: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to send Slack alert: {e}")
            return False

    def detect_failover(self, current_pool):
        """Detect and alert on pool failover"""
        if self.last_seen_pool and current_pool != self.last_seen_pool:
            message = (f"🚨 Failover detected!\n"
                      f"• From: `{self.last_seen_pool}`\n"
                      f"• To: `{current_pool}`\n"
                      f"• Time: {datetime.now().strftime('%H:%M:%S')}\n\n"
                      f"*Action Required*: Check primary pool health and investigate root cause.")
            
            self.send_slack_alert(message, "failover")
            logger.info(f"Failover detected: {self.last_seen_pool} -> {current_pool}")
        
        self.last_seen_pool = current_pool

    def monitor_error_rate(self, log_entry):
        """Monitor and alert on high error rates"""
        # Add to rolling window
        self.request_window.append(log_entry)
        
        # Calculate current error rate
        current_error_rate = self.calculate_error_rate()
        
        # Check if threshold is breached
        if (current_error_rate > self.error_rate_threshold and 
            len(self.request_window) >= self.window_size * 0.5):  # Require at least 50% window filled
            
            message = (f"⚠️ High Error Rate Detected!\n"
                      f"• Current Rate: `{current_error_rate:.2f}%`\n"
                      f"• Threshold: `{self.error_rate_threshold}%`\n"
                      f"• Window Size: `{len(self.request_window)}` requests\n"
                      f"• 5xx Count: `{sum(1 for req in self.request_window if 500 <= req.get('status', 0) < 600)}`\n\n"
                      f"*Action Required*: Investigate upstream services for issues.")
            
            self.send_slack_alert(message, "error_rate")
            logger.warning(f"High error rate: {current_error_rate:.2f}%")

    def process_log_line(self, line):
        """Process a single log line"""
        log_entry = self.parse_log_line(line)
        
        if not log_entry:
            return
        
        # Skip if pool is unknown
        if log_entry['pool'] == 'unknown':
            return
        
        # Detect failover
        self.detect_failover(log_entry['pool'])
        
        # Monitor error rate
        self.monitor_error_rate(log_entry)
        
        # Log for debugging
        logger.debug(f"Processed: {log_entry['pool']} - Status: {log_entry['status']}")

    def tail_log_file(self):
        """Tail the nginx log file continuously"""
        logger.info(f"Starting to tail log file: {self.log_file}")
        
        # Wait for log file to exist
        while not os.path.exists(self.log_file):
            logger.info(f"Waiting for log file: {self.log_file}")
            time.sleep(5)
        
        # Start from end of file
        with open(self.log_file, 'r') as file:
            # Go to end of file
            file.seek(0, 2)
            
            while True:
                line = file.readline()
                if line:
                    self.process_log_line(line.strip())
                else:
                    time.sleep(0.1)  # Small delay when no new lines

    def run(self):
        """Main execution loop"""
        logger.info("Starting Log Watcher service")
        
        if not self.slack_webhook_url:
            logger.warning("SLACK_WEBHOOK_URL not set - alerts will not be sent to Slack")
        
        try:
            self.tail_log_file()
        except KeyboardInterrupt:
            logger.info("Log Watcher stopped by user")
        except Exception as e:
            logger.error(f"Log Watcher crashed: {e}")
            raise

if __name__ == "__main__":
    watcher = LogWatcher()
    watcher.run()