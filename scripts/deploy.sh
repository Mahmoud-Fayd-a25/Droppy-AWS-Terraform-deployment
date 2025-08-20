#!/bin/bash
# deploy.sh - Automated deployment script for multi-account Droppy deployment


set -euo pipefail  # Exit on error, undefined vars, and pipe failures
IFS=$'\n\t'       # Secure Internal Field Separator

# Script configuration
SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

readonly LOG_DIR="${SCRIPT_DIR}/logs"

LOG_FILE=""
LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
readonly LOG_FILE

readonly CONFIG_FILE="${SCRIPT_DIR}/deploy.config"
readonly LOCK_FILE="${SCRIPT_DIR}/.deploy.lock"
readonly BACKUP_DIR="${SCRIPT_DIR}/state-backups"

# Default configuration (can be overridden by config file)
DEFAULT_TIMEOUT=3600  # 1 hour timeout
DEFAULT_RETRY_COUNT=3
DEFAULT_RETRY_DELAY=5

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables
DEPLOYMENT_START_TIME=""
DEPLOYMENT_SUCCESS=false
CLEANUP_REQUIRED=false

# Function to setup logging
setup_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    echo "=== Deployment started at $(date) ===" | tee -a "$LOG_FILE"
}

# Enhanced output functions with logging
print_status() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"
}

print_debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $(date '+%H:%M:%S') $1" | tee -a "$LOG_FILE"
    fi
}

print_header() {
    echo -e "${PURPLE}===============================================${NC}"
    echo -e "${PURPLE}🚀 $1${NC}"
    echo -e "${PURPLE}===============================================${NC}"
}

# Function to load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        print_status "Loading configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        print_warning "No config file found at $CONFIG_FILE, using defaults"
    fi
    
    # Set defaults if not defined
    TIMEOUT=${TIMEOUT:-$DEFAULT_TIMEOUT}
    RETRY_COUNT=${RETRY_COUNT:-$DEFAULT_RETRY_COUNT}
    RETRY_DELAY=${RETRY_DELAY:-$DEFAULT_RETRY_DELAY}
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check required commands
    local required_commands=("terraform" "aws" "jq" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version')
    print_status "Terraform version: $tf_version"
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    print_status "All prerequisites satisfied."
}

# Function to create deployment lock
create_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            print_error "Another deployment is already running (PID: $lock_pid)"
            exit 1
        else
            print_warning "Stale lock file found, removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    CLEANUP_REQUIRED=true
    print_status "Deployment lock created."
}

# Function to remove deployment lock
remove_lock() {
    if [[ "$CLEANUP_REQUIRED" == "true" && -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        print_status "Deployment lock removed."
    fi
}

# Function to backup state files
backup_state() {
    local account_dir=$1
    local profile_name=$2
    
    print_status "Backing up state for $profile_name..."
    mkdir -p "$BACKUP_DIR"
    
    local backup_file
    backup_file="${BACKUP_DIR}/terraform.tfstate.${profile_name}.$(date +%Y%m%d-%H%M%S).backup"
    
    if [[ -f "${account_dir}/terraform.tfstate" ]]; then
        cp "${account_dir}/terraform.tfstate" "$backup_file"
        print_status "State backed up to: $backup_file"
    else
        print_warning "No state file found for $profile_name"
    fi
}

# Function to validate AWS credentials and permissions
validate_aws_credentials() {
    local profile_name=$1
    
    print_status "Validating AWS credentials for profile: $profile_name"
    
    # Set the AWS profile
    export AWS_PROFILE=$profile_name
    
    # Check if profile exists
    if ! aws configure list-profiles | grep -q "^${profile_name}$"; then
        print_error "AWS profile '$profile_name' not found."
        return 1
    fi
    
    # Validate credentials
    local caller_identity
    if ! caller_identity=$(aws sts get-caller-identity 2>/dev/null); then
        print_error "Failed to validate AWS credentials for profile '$profile_name'"
        return 1
    fi
    
    local account_id
    account_id=$(echo "$caller_identity" | jq -r '.Account')
    print_status "Authenticated as account: $account_id"
    
    # Test basic permissions
    if ! aws sts get-session-token --duration-seconds 900 &> /dev/null; then
        print_warning "Limited permissions detected for profile '$profile_name'"
    fi
    
    return 0
}

# Enhanced retry mechanism
retry_command() {
    local max_attempts=$1
    local delay=$2
    local command=("${@:3}")
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_debug "Attempt $attempt of $max_attempts: ${command[*]}"
        
        if "${command[@]}"; then
            return 0
        else
            local exit_code=$?
            if [[ $attempt -eq $max_attempts ]]; then
                print_error "Command failed after $max_attempts attempts: ${command[*]}"
                return $exit_code
            fi
            
            print_warning "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"
            ((attempt++))
        fi
    done
}

# Function to handle Terraform operations with enhanced error handling
run_terraform() {
    local account_dir=$1
    local profile_name=$2
    local plan_file="tfplan-${profile_name}"
    local original_dir
    original_dir=$(pwd)

    print_header "Deploying infrastructure for ${profile_name}"
    
    # Validate directory exists
    if [[ ! -d "$account_dir" ]]; then
        print_error "Directory $account_dir does not exist"
        return 1
    fi
    
    cd "$account_dir" || { 
        print_error "Failed to enter directory $account_dir"
        return 1
    }

    # Validate AWS credentials first
    if ! validate_aws_credentials "$profile_name"; then
        cd "$original_dir"
        return 1
    fi

    # Backup existing state
    backup_state "." "$profile_name"

    # Initialize Terraform with retry
    print_status "Initializing Terraform..."
    if ! retry_command "$RETRY_COUNT" "$RETRY_DELAY" terraform init -upgrade; then
        print_error "Terraform initialization failed after $RETRY_COUNT attempts"
        cd "$original_dir"
        return 1
    fi

    # Validate configuration
    print_status "Validating Terraform configuration..."
    if ! terraform validate; then
        print_error "Terraform configuration validation failed"
        cd "$original_dir"
        return 1
    fi

    # Format check (non-blocking)
    if ! terraform fmt -check=true -diff=true; then
        print_warning "Terraform formatting issues detected. Run 'terraform fmt' to fix."
    fi

    # Security scan with tfsec if available
    if command -v tfsec &> /dev/null; then
        print_status "Running security scan with tfsec..."
        if ! tfsec . --soft-fail; then
            print_warning "Security issues detected. Review tfsec output above."
        fi
    fi

    # Check for existing plan file
    if [[ -f "$plan_file" ]]; then
        print_warning "Found existing plan file ($plan_file)."
        read -p "Do you want to use the existing plan? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$plan_file"
            print_status "Existing plan file removed."
        fi
    fi

    # Create execution plan if needed
    if [[ ! -f "$plan_file" ]]; then
        print_status "Creating execution plan..."
        if ! retry_command "$RETRY_COUNT" "$RETRY_DELAY" terraform plan -detailed-exitcode -out="$plan_file"; then
            local plan_exit_code=$?
            if [[ $plan_exit_code -eq 2 ]]; then
                print_status "Plan created successfully with changes detected."
            else
                print_error "Terraform plan failed"
                cd "$original_dir"
                return 1
            fi
        else
            print_status "No changes detected in plan."
        fi
    fi

    # Show plan summary
    print_status "Plan summary:"
    terraform show -no-color "$plan_file" | head -20

    # Confirm before apply (unless auto-approved)
    if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
        echo
        read -p "Do you want to apply this plan? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Deployment cancelled by user."
            cd "$original_dir"
            return 1
        fi
    fi

    # Apply the plan with timeout
    print_status "Applying the plan..."
    if ! timeout "$TIMEOUT" terraform apply "$plan_file"; then
        print_error "Terraform apply failed or timed out"
        print_error "State may be inconsistent. Please review and fix manually."
        cd "$original_dir"
        return 1
    fi

    # Clean up plan file
    rm -f "$plan_file"

    print_status "✅ Deployment for ${profile_name} completed successfully!"
    cd "$original_dir"
    return 0
}

# Function to get outputs safely
get_terraform_output() {
    local account_dir=$1
    local output_name=$2
    local profile_name=$3
    
    print_debug "Getting output '$output_name' from $account_dir"
    
    cd "$account_dir" || {
        print_error "Failed to enter directory $account_dir"
        return 1
    }
    
    export AWS_PROFILE=$profile_name
    
    local output_value
    if output_value=$(terraform output -raw "$output_name" 2>/dev/null); then
        echo "$output_value"
        cd - > /dev/null
        return 0
    else
        print_error "Failed to get output '$output_name' from $account_dir"
        cd - > /dev/null
        return 1
    fi
}

# Function to generate deployment report
generate_report() {
    local report_file
    report_file="${LOG_DIR}/deployment-report-$(date +%Y%m%d-%H%M%S).txt"
    
    print_status "Generating deployment report..."
    
    {
        echo "=========================================="
        echo "Droppy Multi-Account Deployment Report"
        echo "=========================================="
        echo "Deployment Date: $(date)"
        echo "Deployment Duration: $(($(date +%s) - DEPLOYMENT_START_TIME)) seconds"
        echo "Status: $( [[ "$DEPLOYMENT_SUCCESS" == "true" ]] && echo "SUCCESS" || echo "FAILED" )"
        echo ""
        echo "Configuration:"
        echo "- Timeout: ${TIMEOUT}s"
        echo "- Retry Count: $RETRY_COUNT"
        echo "- Retry Delay: ${RETRY_DELAY}s"
        echo ""
        
        if [[ "$DEPLOYMENT_SUCCESS" == "true" ]]; then
            echo "Deployment Outputs:"
            echo "- Jump Host Public IP: ${JUMPHOST_IP:-'N/A'}"
            echo "- Droppy URL: ${DROPPY_URL:-'N/A'}"
            echo ""
            echo "Next Steps:"
            echo "1. RDP to the jump host: ${JUMPHOST_IP:-'N/A'}"
            echo "2. Open a web browser on the jump host"
            echo "3. Navigate to: ${DROPPY_URL:-'N/A'}"
        fi
        
        echo ""
        echo "Log File: $LOG_FILE"
        echo "Report File: $report_file"
    } > "$report_file"
    
    print_status "Report generated: $report_file"
}

# Function to cleanup on exit
cleanup() {
    local exit_code=$?
    
    print_status "Performing cleanup..."
    remove_lock
    
    if [[ $exit_code -ne 0 ]]; then
        print_error "Deployment failed with exit code: $exit_code"
        DEPLOYMENT_SUCCESS=false
    fi
    
    generate_report
    
    echo "=== Deployment ended at $(date) ===" | tee -a "$LOG_FILE"
    exit $exit_code
}

# Function to handle interruption
handle_interrupt() {
    print_warning "Deployment interrupted by user (Ctrl+C)"
    print_status "Cleaning up..."
    cleanup
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Enhanced multi-account Droppy deployment script

OPTIONS:
    -h, --help          Show this help message
    -c, --config FILE   Use custom config file (default: ./deploy.config)
    -a, --auto-approve  Auto-approve Terraform plans (skip confirmation)
    -d, --debug         Enable debug output
    -t, --timeout SEC   Set deployment timeout in seconds (default: 3600)
    --dry-run          Show what would be deployed without making changes

EXAMPLES:
    $0                          # Normal deployment with prompts
    $0 --auto-approve          # Automated deployment
    $0 --debug --timeout 7200  # Debug mode with 2-hour timeout
    $0 --config prod.config    # Use custom config file

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -a|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main deployment logic
main() {
    DEPLOYMENT_START_TIME=$(date +%s)
    
    # Set up signal handlers
    trap cleanup EXIT
    trap handle_interrupt INT TERM
    
    # Parse arguments
    parse_arguments "$@"
    
    # Setup logging
    setup_logging
    
    print_header "Multi-Account Droppy Deployment"
    
    # Load configuration
    load_config
    
    # Create deployment lock
    create_lock
    
    # Check prerequisites
    check_prerequisites
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        print_status "DRY RUN MODE - No changes will be made"
        print_status "Would deploy to:"
        print_status "  - Account A (profile: account-a)"
        print_status "  - Account B (profile: account-b)"
        exit 0
    fi
    
    # Deploy Account A
    if ! run_terraform "account-a" "account-a"; then
        print_error "Failed to deploy Account A"
        exit 1
    fi

    # Deploy Account B
    if ! run_terraform "account-b" "account-b"; then
        print_error "Failed to deploy Account B"
        exit 1
    fi

    # Get outputs with error handling
    print_status "Retrieving deployment outputs..."
    
    if JUMPHOST_IP=$(get_terraform_output "account-b" "jumphost_public_ip" "account-b"); then
        print_status "Jump Host Public IP: $JUMPHOST_IP"
    else
        print_error "Failed to retrieve jumphost_public_ip"
        exit 1
    fi
    
    if DROPPY_URL=$(get_terraform_output "account-b" "droppy_url" "account-b"); then
        print_status "Droppy URL: $DROPPY_URL"
    else
        print_error "Failed to retrieve droppy_url"
        exit 1
    fi

    # Mark deployment as successful
    DEPLOYMENT_SUCCESS=true
    
    # Display final results
    print_header "Deployment Complete! 🎉"
    echo ""
    echo "🎉 Multi-account Droppy deployment completed successfully!"
    echo ""
    echo "📋 Connection Details:"
    echo "   Jump Host Public IP: $JUMPHOST_IP"
    echo "   Droppy URL (from jump host): $DROPPY_URL"
    echo ""
    echo "🔗 Next Steps:"
    echo "   1. RDP to the jump host: $JUMPHOST_IP"
    echo "   2. Open a web browser on the jump host"
    echo "   3. Navigate to: $DROPPY_URL"
    echo ""
    echo "⚠️  Security Recommendations:"
    echo "   • Restrict RDP access to your IP range in the security group"
    echo "   • Enable MFA for AWS accounts"
    echo "   • Regularly rotate access keys"
    echo "   • Monitor CloudTrail logs for unusual activity"
    echo ""
    echo "📁 Logs and Reports:"
    echo "   • Deployment log: $LOG_FILE"
    echo "   • State backups: $BACKUP_DIR"
    echo ""
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi