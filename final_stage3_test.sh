#!/bin/bash

echo "================================================"
echo "   FINAL STAGE 3 VALIDATION"
echo "================================================"

# Test 1: Enhanced Logging
echo -e "\n[TEST] Enhanced Logging Format"
if tail -1 logs/access.log 2>/dev/null | grep -q "pool:"; then
    echo "✅ PASS - Enhanced logging with pool information"
    echo "   Sample: $(tail -1 logs/access.log | cut -c1-80)..."
else
    echo "❌ FAIL - Default nginx logging format"
fi

# Test 2: Watcher Processing
echo -e "\n[TEST] Alert Watcher Processing"
if docker-compose logs alert_watcher --tail=3 2>/dev/null | grep -q "Processed\|pool"; then
    echo "✅ PASS - Watcher processing enhanced logs"
else
    echo "⚠️  WARNING - Watcher may not be processing enhanced format"
fi

# Test 3: Complete Setup
echo -e "\n[TEST] Complete Setup"
services_running=$(docker-compose ps | grep -c "Up\|Started")
if [[ $services_running -eq 4 ]]; then
    echo "✅ PASS - All 4 services running"
else
    echo "❌ FAIL - Only $services_running services running (expected 4)"
fi

# Test 4: File Structure
echo -e "\n[TEST] File Structure"
missing=0
for file in docker-compose.yml nginx.conf watcher/watcher.py .env.example runbook.md README.md; do
    [[ -f "$file" ]] || { echo "❌ MISSING: $file"; ((missing++)); }
done
if [[ $missing -eq 0 ]]; then
    echo "✅ PASS - All required files present"
else
    echo "❌ FAIL - Missing $missing files"
fi

echo -e "\n================================================"
if [[ $missing -eq 0 ]] && tail -1 logs/access.log 2>/dev/null | grep -q "pool:"; then
    echo "🎉 STAGE 3 READY FOR SUBMISSION!"
    echo ""
    echo "Required screenshots:"
    echo "1. Enhanced log format (pool: information visible)"
    echo "2. Alert watcher logs" 
    echo "3. Service status"
else
    echo "⚠️  Need to fix enhanced logging first"
fi
echo "================================================"
