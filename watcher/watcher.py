#!/usr/bin/env python3
"""
Nginx Log Watcher for Blue/Green Deployment Monitoring
"""
import os
import time
import re
import requests
import json
import logging
from collections import deque

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class LogWatcher:
    def __init__(self):
        self.slack_webhook = os.getenv('SLACK_WEBHOOK_URL', '')
        self.last_pool = None
        logger.info(f"Watcher started. Slack webhook: {'Configured' if self.slack_webhook else 'Not configured'}")
        
    def parse_log_line(self, line):
        """Parse enhanced log format"""
        try:
            # Parse key=value pairs
            pattern = r'(\w+):([^|]+)'
            matches = re.findall(pattern, line)
            log_data = dict(matches)
            
            pool = log_data.get('pool', 'unknown')
            status = log_data.get('status', '0')
            
            return {
                'pool': pool,
                'status': int(status) if status.isdigit() else 0,
                'upstream_status': log_data.get('upstream_status', ''),
                'timestamp': log_data.get('time', '')
            }
        except Exception as e:
            return None
    
    def send_slack_alert(self, message):
        """Send alert to Slack"""
        if not self.slack_webhook or 'placeholder' in self.slack_webhook:
            logger.warning(f"Would send Slack alert: {message}")
            return False
            
        payload = {
            "text": f"🚨 Blue/Green Alert: {message}",
            "username": "Deployment Monitor",
            "icon_emoji": ":warning:"
        }
        
        try:
            response = requests.post(
                self.slack_webhook,
                json=payload,
                headers={'Content-Type': 'application/json'},
                timeout=5
            )
            if response.status_code == 200:
                logger.info(f"Slack alert sent: {message}")
                return True
            else:
                logger.error(f"Slack API error: {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Slack request failed: {e}")
            return False
    
    def detect_failover(self, current_pool):
        """Detect and alert on pool changes"""
        if self.last_pool and current_pool != self.last_pool and current_pool != 'unknown':
            message = f"Failover detected! From {self.last_pool} to {current_pool}"
            logger.info(message)
            self.send_slack_alert(message)
        
        if current_pool != 'unknown':
            self.last_pool = current_pool
    
    def process_logs(self):
        """Process new log lines"""
        log_file = '/var/log/nginx/access.log'
        
        try:
            if not os.path.exists(log_file):
                logger.warning(f"Log file not found: {log_file}")
                return
                
            with open(log_file, 'r') as f:
                lines = f.readlines()
                for line in lines:
                    log_data = self.parse_log_line(line.strip())
                    if log_data and log_data['pool']:
                        logger.info(f"Processed: pool={log_data['pool']}, status={log_data['status']}")
                        self.detect_failover(log_data['pool'])
        except Exception as e:
            logger.error(f"Error processing logs: {e}")
    
    def run(self):
        """Main loop"""
        logger.info("Starting log watcher service")
        
        while True:
            self.process_logs()
            time.sleep(5)

if __name__ == "__main__":
    watcher = LogWatcher()
    watcher.run()
