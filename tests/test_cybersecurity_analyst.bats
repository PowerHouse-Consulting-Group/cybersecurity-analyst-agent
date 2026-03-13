#!/usr/bin/env bats

setup() {
    export SCRIPT_DIR="${BATS_TEST_DIRNAME}/.."
    export MAIN_SCRIPT="${SCRIPT_DIR}/cybersecurity_analyst.sh"
    
    # Backup original .env if it exists
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        mv "${SCRIPT_DIR}/.env" "${SCRIPT_DIR}/.env.bak"
    fi
}

teardown() {
    # Restore original .env
    if [ -f "${SCRIPT_DIR}/.env.bak" ]; then
        mv "${SCRIPT_DIR}/.env.bak" "${SCRIPT_DIR}/.env"
    fi
    # Cleanup temp env files
    rm -f "${SCRIPT_DIR}/.env"
}

@test "load_config fails if .env is missing" {
    run bash -c "source ${MAIN_SCRIPT} && load_config"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Configuration file not found"* ]]
}

@test "load_config succeeds with basic config" {
    cat << 'ENV' > "${SCRIPT_DIR}/.env"
YOUR_EMAIL="test@example.com"
PROJECT_ID="test-project"
MODEL_ID="test-model"
LLM_PROVIDER="gemini"
ENV
    run bash -c "source ${MAIN_SCRIPT} && load_config && echo \$LLM_PROVIDER"
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == "gemini" ]]
}

@test "load_config sets correct defaults" {
    cat << 'ENV' > "${SCRIPT_DIR}/.env"
YOUR_EMAIL="test@example.com"
PROJECT_ID="test-project"
MODEL_ID="test-model"
ENV
    run bash -c "source ${MAIN_SCRIPT} && load_config && echo \$TOP_N"
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == "20" ]]
}

@test "parse_logs runs without errors when logs are missing" {
    # Provide empty paths to skip log parsing but not fail
    cat << 'ENV' > "${SCRIPT_DIR}/.env"
YOUR_EMAIL="test@example.com"
PROJECT_ID="test-project"
MODEL_ID="test-model"
APACHE_LOG_DIR="/tmp/nonexistent_apache"
NGINX_LOG_DIR="/tmp/nonexistent_nginx"
SYSTEM_LOG_PATH="/tmp/nonexistent_syslog"
MAIL_LOG_PATH="/tmp/nonexistent_mail"
MYSQL_SLOW_LOG_PATH="/tmp/nonexistent_mysql"
USE_JOURNALCTL="false"
ENV
    # Using source and calling the function should output Pre-check complete 
    run bash -c "source ${MAIN_SCRIPT} && load_config && parse_logs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pre-check complete"* ]]
}
