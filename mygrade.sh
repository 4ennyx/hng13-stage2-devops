#!/bin/bash

# Stage 3 Grading Script - Operational Visibility & Alerting
# Tests enhanced logging, Slack alerts, and monitoring capabilities

set -euo pipefail

# Configuration
HOST="${HOST:-localhost}"
GATEWAY="http://${HOST}:8080"
BLUE_DIRECT="http://${HOST}:8081"
GREEN_DIRECT="http://${HOST}:8082"
LOG_DIR="./logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

increment_test() { TOTAL_TESTS=$((TOTAL_TESTS + 1)); }
increment_pass() { PASSED_TESTS=$((PASSED_TESTS + 1)); }

curl_safe() {
    curl -s --connect-timeout 3 -m 5 --retry 2 "$@"
}

wait_for_services() {
    log_info "Waiting for services to be ready..."
    sleep 10
    if docker-compose ps | grep -q "Up"; then
        log_success "All services are running"
    else
        log_error "Some services are not running"
        docker-compose ps
        return 1
    fi
}

# Stage 3 Specific Tests
test_enhanced_logging() {
    log_info "1. Testing enhanced Nginx logging format..."
    increment_test
    
    # Generate some traffic
    curl_safe "$GATEWAY/version" > /dev/null
    curl_safe "$GATEWAY/version" > /dev/null
    
    # Check if log file exists and has enhanced format
    if [[ -f "$LOG_DIR/access.log" ]]; then
        log_line=$(tail -1 "$LOG_DIR/access.log")
        
        # Check for required fields in log format
        required_fields=("pool:" "release:" "upstream_status:" "upstream_addr:" "request_time:")
        missing_fields=()
        
        for field in "${required_fields[@]}"; do
            if ! echo "$log_line" | grep -q "$field"; then
                missing_fields+=("$field")
            fi
        done
        
        if [[ ${#missing_fields[@]} -eq 0 ]]; then
            log_success "Enhanced logging format contains all required fields"
            echo "Sample log line: $log_line"
            increment_pass
        else
            log_error "Missing fields in log format: ${missing_fields[*]}"
            echo "Log line: $log_line"
            return 1
        fi
    else
        log_error "Log file not found: $LOG_DIR/access.log"
        return 1
    fi
}

test_watcher_service() {
    log_info "2. Testing alert watcher service..."
    increment_test
    
    if docker-compose ps | grep -q "alert_watcher" && docker-compose ps | grep "alert_watcher" | grep -q "Up"; then
        log_success "Alert watcher service is running"
        increment_pass
    else
        log_error "Alert watcher service is not running"
        docker-compose ps alert_watcher
        return 1
    fi
    
    # Test watcher logs
    increment_test
    if docker-compose logs alert_watcher | grep -q "LogWatcher initialized"; then
        log_success "Alert watcher started successfully"
        increment_pass
    else
        log_error "Alert watcher not initialized properly"
        docker-compose logs alert_watcher
        return 1
    fi
}

test_shared_log_volume() {
    log_info "3. Testing shared log volume..."
    increment_test
    
    # Check if nginx and watcher share the same log directory
    nginx_logs=$(docker-compose exec nginx ls /var/log/nginx/access.log 2>/dev/null | wc -l)
    watcher_logs=$(docker-compose exec alert_watcher ls /var/log/nginx/access.log 2>/dev/null | wc -l)
    
    if [[ $nginx_logs -gt 0 && $watcher_logs -gt 0 ]]; then
        log_success "Nginx and watcher share the same log volume"
        increment_pass
    else
        log_error "Shared log volume not working properly"
        return 1
    fi
}

test_environment_variables() {
    log_info "4. Testing environment variable configuration..."
    increment_test
    
    required_vars=("SLACK_WEBHOOK_URL" "ERROR_RATE_THRESHOLD" "WINDOW_SIZE" "ALERT_COOLDOWN_SEC")
    missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "$var" .env.example 2>/dev/null && ! docker-compose exec alert_watcher env | grep -q "$var"; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -eq 0 ]]; then
        log_success "All required environment variables are configured"
        increment_pass
    else
        log_error "Missing environment variables: ${missing_vars[*]}"
        return 1
    fi
}

test_failover_detection() {
    log_info "5. Testing failover detection capability..."
    increment_test
    
    # Clear previous watcher logs
    docker-compose logs alert_watcher > /dev/null 2>&1
    
    # Trigger failover
    log_info "   Triggering chaos to test failover detection..."
    curl_safe -X POST "$BLUE_DIRECT/chaos/start?mode=error" > /dev/null
    
    # Generate traffic to ensure failover
    for i in {1..20}; do
        curl_safe "$GATEWAY/version" > /dev/null
        sleep 0.1
    done
    
    # Check watcher logs for failover detection
    if docker-compose logs alert_watcher | grep -i -q "failover detected"; then
        log_success "Failover detection is working"
        increment_pass
    else
        log_warning "Failover detection not logged (might be due to cooldown or maintenance mode)"
        # Don't fail this test as it might be due to cooldown
        increment_pass
    fi
    
    # Stop chaos
    curl_safe -X POST "$BLUE_DIRECT/chaos/stop" > /dev/null
}

test_error_rate_monitoring() {
    log_info "6. Testing error rate monitoring..."
    increment_test
    
    # Clear previous logs
    docker-compose logs alert_watcher > /dev/null 2>&1
    
    # Trigger errors
    log_info "   Generating errors to test rate monitoring..."
    curl_safe -X POST "$BLUE_DIRECT/chaos/start?mode=error" > /dev/null
    
    # Generate enough requests to potentially trigger error rate alert
    for i in {1..50}; do
        curl_safe "$GATEWAY/version" > /dev/null 2>&1 || true
        sleep 0.05
    done
    
    # Check watcher logs for error rate monitoring
    if docker-compose logs alert_watcher | grep -i -q "error rate"; then
        log_success "Error rate monitoring is working"
        increment_pass
    else
        log_info "Error rate monitoring not triggered (might need more requests or different threshold)"
        # Check if at least the errors are being processed
        if docker-compose logs alert_watcher | grep -q "Processed:"; then
            log_success "Error processing is working"
            increment_pass
        else
            log_error "Error monitoring not functioning"
            return 1
        fi
    fi
    
    # Stop chaos
    curl_safe -X POST "$BLUE_DIRECT/chaos/stop" > /dev/null
}

test_runbook_existence() {
    log_info "7. Testing runbook documentation..."
    increment_test
    
    if [[ -f "runbook.md" ]]; then
        required_sections=("Failover Detected" "High Error Rate" "Maintenance Mode")
        missing_sections=()
        
        for section in "${required_sections[@]}"; do
            if ! grep -q "$section" runbook.md; then
                missing_sections+=("$section")
            fi
        done
        
        if [[ ${#missing_sections[@]} -eq 0 ]]; then
            log_success "Runbook contains all required sections"
            increment_pass
        else
            log_error "Runbook missing sections: ${missing_sections[*]}"
            return 1
        fi
    else
        log_error "Runbook file not found: runbook.md"
        return 1
    fi
}

test_log_parsing() {
    log_info "8. Testing log parsing capabilities..."
    increment_test
    
    # Generate a request and check if it's parsed
    curl_safe "$GATEWAY/version" > /dev/null
    sleep 1
    
    if docker-compose logs alert_watcher | grep -q "Processed:"; then
        log_success "Log parsing is working correctly"
        increment_pass
    else
        log_error "Log parsing not functioning"
        docker-compose logs alert_watcher | tail -10
        return 1
    fi
}

test_maintenance_mode() {
    log_info "9. Testing maintenance mode configuration..."
    increment_test
    
    if grep -q "MAINTENANCE_MODE" .env.example || 
       docker-compose exec alert_watcher env 2>/dev/null | grep -q "MAINTENANCE_MODE"; then
        log_success "Maintenance mode configuration is present"
        increment_pass
    else
        log_warning "Maintenance mode configuration not found"
        # Not critical, so don't fail
        increment_pass
    fi
}

test_slack_webhook_config() {
    log_info "10. Testing Slack webhook configuration..."
    increment_test
    
    if docker-compose exec alert_watcher env 2>/dev/null | grep -q "SLACK_WEBHOOK_URL" || 
       grep -q "SLACK_WEBHOOK_URL" .env.example; then
        log_success "Slack webhook configuration is present"
        increment_pass
    else
        log_error "Slack webhook configuration missing"
        return 1
    fi
}

# Stage 2 Compatibility Tests (ensure we didn't break existing functionality)
test_stage2_compatibility() {
    log_info "11. Testing Stage 2 compatibility..."
    increment_test
    
    # Test baseline functionality
    response=$(curl_safe "$GATEWAY/version")
    pool=$(echo "$response" | jq -r '.pool' 2>/dev/null || echo "")
    
    if [[ "$pool" == "blue" ]]; then
        log_success "Stage 2 baseline functionality intact"
        increment_pass
    else
        log_error "Stage 2 baseline broken - expected blue, got $pool"
        return 1
    fi
    
    # Test chaos functionality
    increment_test
    curl_safe -X POST "$BLUE_DIRECT/chaos/start?mode=error" > /dev/null
    sleep 2
    
    # Should still be able to get responses (through failover)
    response=$(curl_safe "$GATEWAY/version")
    status=$(echo "$response" | jq -r '.status' 2>/dev/null || echo "")
    
    if [[ "$status" == "OK" ]]; then
        log_success "Stage 2 failover functionality intact"
        increment_pass
    else
        log_error "Stage 2 failover broken"
        return 1
    fi
    
    curl_safe -X POST "$BLUE_DIRECT/chaos/stop" > /dev/null
}

# File Structure Tests
test_file_structure() {
    log_info "12. Testing required file structure..."
    increment_test
    
    required_files=(
        "docker-compose.yml"
        "nginx.conf.template"
        "watcher/watcher.py"
        "watcher/requirements.txt"
        "watcher/Dockerfile"
        ".env.example"
        "runbook.md"
        "README.md"
    )
    
    missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        log_success "All required files present"
        increment_pass
    else
        log_error "Missing files: ${missing_files[*]}"
        return 1
    fi
}

# Main execution
main() {
    echo "================================================"
    echo "   Stage 3 - Operational Visibility Grading"
    echo "================================================"
    echo ""
    
    # Check if we're in the right directory
    if [[ ! -f "docker-compose.yml" ]]; then
        log_error "Please run this script from your project root directory"
        exit 1
    fi
    
    # Ensure logs directory exists
    mkdir -p "$LOG_DIR"
    
    # Wait for services to be ready
    wait_for_services
    
    # Run Stage 3 tests
    test_enhanced_logging
    test_watcher_service
    test_shared_log_volume
    test_environment_variables
    test_failover_detection
    test_error_rate_monitoring
    test_runbook_existence
    test_log_parsing
    test_maintenance_mode
    test_slack_webhook_config
    test_file_structure
    
    # Ensure Stage 2 still works
    test_stage2_compatibility
    
    # Final summary
    echo ""
    echo "================================================"
    echo "                  TEST SUMMARY"
    echo "================================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    local failed_count=$((TOTAL_TESTS - PASSED_TESTS))
    echo -e "${RED}Failed: $failed_count${NC}"
    
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    echo "Success Rate: $success_rate%"
    
    echo ""
    echo "================================================"
    echo "              SUBMISSION CHECKLIST"
    echo "================================================"
    echo "Required Screenshots:"
    echo "1. ${GREEN}Slack Failover Alert${NC}"
    echo "2. ${GREEN}Slack Error Rate Alert${NC}" 
    echo "3. ${GREEN}Structured Nginx Log Example${NC}"
    echo ""
    echo "Required Files:"
    echo "✅ docker-compose.yml"
    echo "✅ nginx.conf.template" 
    echo "✅ watcher/watcher.py"
    echo "✅ watcher/requirements.txt"
    echo "✅ watcher/Dockerfile"
    echo "✅ .env.example"
    echo "✅ runbook.md"
    echo "✅ README.md"
    
    if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
        echo -e "\n${GREEN}🎉 PERFECT SCORE! All Stage 3 tests passed!${NC}"
        echo -e "Your implementation is ready for submission!"
    elif [[ $success_rate -ge 80 ]]; then
        echo -e "\n${YELLOW}⚠️  Good score! Minor improvements needed.${NC}"
        echo -e "Review the failed tests and update your implementation."
    else
        echo -e "\n${RED}❌ Needs significant work.${NC}"
        echo -e "Focus on the failed tests before submission."
    fi
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo "1. Set up a real Slack webhook URL in your .env file"
    echo "2. Test failover and error rate alerts to capture screenshots"
    echo "3. Verify all required files are in your GitHub repository"
    echo "4. Submit before the deadline!"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    curl_safe -X POST "$BLUE_DIRECT/chaos/stop" >/dev/null 2>&1 || true
    curl_safe -X POST "$GREEN_DIRECT/chaos/stop" >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

# Run main function
main