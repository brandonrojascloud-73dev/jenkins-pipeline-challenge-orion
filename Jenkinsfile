pipeline {
    agent any
    
    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(daysToKeepStr: '30'))
        timeout(time: 45, unit: 'MINUTES')
    }
    
    environment {
        NOTEPAD_URL = 'https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.portable.zip'
        LOCK_FILE = "${WORKSPACE}/notepad_monitor.lock"
        PREVIOUS_DIR = "${WORKSPACE}/previous_version"
        CURRENT_DIR = "${WORKSPACE}/current_version"
        DOWNLOAD_DIR = "${WORKSPACE}/downloads"
        TEMP_DIR = "${WORKSPACE}/temp"
        DIFF_LOG = "${WORKSPACE}/version_diff.log"
        
        EMAIL_TO = 'admin@company.com'
        EMAIL_FROM = 'jenkins@company.com'
        
        LOCK_THRESHOLD_DAYS = '15'
        LOCK_THRESHOLD_SECONDS = '1296000'
    }
    
    stages {
        stage('Setup Workspace') {
            steps {
                script {
                    echo "Initializing Notepad++ version monitor pipeline"
                    echo "Workspace location: ${WORKSPACE}"
                    echo "Execution time: ${new Date()}"
                    
                    sh '''
                        mkdir -p "${DOWNLOAD_DIR}"
                        mkdir -p "${CURRENT_DIR}"
                        mkdir -p "${PREVIOUS_DIR}"
                        mkdir -p "${TEMP_DIR}"
                        
                        echo "Directory structure created successfully"
                    '''
                }
            }
        }
        
        stage('Evaluate Lock Status') {
            steps {
                script {
                    echo "Checking for existing lock file"
                    
                    if (fileExists(env.LOCK_FILE)) {
                        echo "Lock file detected at: ${env.LOCK_FILE}"
                        
                        def lockAgeSeconds = sh(
                            script: '''
                                if [ -f "${LOCK_FILE}" ]; then
                                    # Get file modification time (works on both Linux and macOS)
                                    if stat -c %Y "${LOCK_FILE}" >/dev/null 2>&1; then
                                        # Linux
                                        lock_time=$(stat -c %Y "${LOCK_FILE}")
                                    else
                                        # macOS
                                        lock_time=$(stat -f %m "${LOCK_FILE}")
                                    fi
                                    current_time=$(date +%s)
                                    echo $((current_time - lock_time))
                                else
                                    echo "0"
                                fi
                            ''',
                            returnStdout: true
                        ).trim().toInteger()
                        
                        echo "Lock file age: ${lockAgeSeconds} seconds"
                        echo "Threshold: ${env.LOCK_THRESHOLD_SECONDS} seconds (${env.LOCK_THRESHOLD_DAYS} days)"
                        
                        if (lockAgeSeconds >= env.LOCK_THRESHOLD_SECONDS.toInteger()) {
                            echo "Lock file exceeds ${env.LOCK_THRESHOLD_DAYS} day threshold"
                            echo "Proceeding with version check and notification"
                            env.SHOULD_NOTIFY = 'true'
                            env.SKIP_LOCK_CREATION = 'true'
                        } else {
                            def remainingDays = ((env.LOCK_THRESHOLD_SECONDS.toInteger() - lockAgeSeconds) / 86400).round(1)
                            echo "Lock file is only ${(lockAgeSeconds / 86400).round(1)} days old"
                            echo "Will notify in ${remainingDays} more days"
                            echo "Exiting early - notification period not reached"
                            currentBuild.result = 'SUCCESS'
                            return
                        }
                    } else {
                        echo "No lock file found - this appears to be first run or lock was cleared"
                        env.SHOULD_NOTIFY = 'false'
                        env.SKIP_LOCK_CREATION = 'false'
                    }
                }
            }
        }
        
        stage('Download Current Version') {
            when {
                not { 
                    equals expected: 'SUCCESS', actual: currentBuild.result 
                }
            }
            
            steps {
                script {
                    echo "Starting download of latest Notepad++ portable version"
                    echo "Source URL: ${env.NOTEPAD_URL}"
                    
                    retry(3) {
                        timeout(time: 15, unit: 'MINUTES') {
                            sh '''
                                set -e
                                
                                echo "Initiating download attempt..."
                                
                                curl -L \
                                    --max-time 900 \
                                    --connect-timeout 60 \
                                    --retry 2 \
                                    --retry-delay 10 \
                                    --retry-max-time 600 \
                                    --fail \
                                    --silent \
                                    --show-error \
                                    --location \
                                    -o "${DOWNLOAD_DIR}/notepad_current.zip" \
                                    "${NOTEPAD_URL}"
                                
                                # Verify the download completed
                                if [ ! -f "${DOWNLOAD_DIR}/notepad_current.zip" ]; then
                                    echo "Error: Download file not found after curl completion"
                                    exit 1
                                fi
                                
                                # Check if file has reasonable size for Notepad++
                                file_size=$(wc -c < "${DOWNLOAD_DIR}/notepad_current.zip")
                                min_size=1048576  # 1MB minimum
                                
                                if [ "$file_size" -lt "$min_size" ]; then
                                    echo "Error: Downloaded file is too small (${file_size} bytes)"
                                    echo "Expected at least ${min_size} bytes for Notepad++ portable"
                                    exit 1
                                fi
                                
                                echo "Download verification passed - file size: ${file_size} bytes"
                                
                                # Extract the archive
                                echo "Extracting archive to current version directory"
                                cd "${CURRENT_DIR}"
                                
                                unzip -q "${DOWNLOAD_DIR}/notepad_current.zip"
                                if [ $? -ne 0 ]; then
                                    echo "Error: Failed to extract the downloaded archive"
                                    exit 1
                                fi
                                
                                echo "Extraction completed successfully"
                                
                                # List extracted contents for verification
                                echo "Extracted files:"
                                find "${CURRENT_DIR}" -type f | head -10
                            '''
                        }
                    }
                }
            }
            
            post {
                failure {
                    script {
                        echo "Download failed after multiple retry attempts"
                        
                        // Send failure notification if email is configured
                        try {
                            emailext (
                                subject: "Notepad++ Monitor: Download Failed",
                                body: """
Download of Notepad++ portable failed after multiple attempts.

Job: ${env.JOB_NAME}
Build: ${env.BUILD_NUMBER}
Time: ${new Date()}
URL: ${env.BUILD_URL}

Please check the Jenkins logs and network connectivity.
""",
                                to: env.EMAIL_TO
                            )
                        } catch (Exception e) {
                            echo "Could not send failure notification email: ${e.message}"
                        }
                    }
                }
            }
        }
        
        stage('Compare With Previous') {
            when {
                not { 
                    equals expected: 'SUCCESS', actual: currentBuild.result 
                }
            }
            
            steps {
                script {
                    echo "Starting version comparison analysis"
                    
                    def versionChanged = false
                    
                    // Check if we have a previous version to compare against
                    def hasPreviousVersion = sh(
                        script: "ls -A '${env.PREVIOUS_DIR}' 2>/dev/null | wc -l",
                        returnStdout: true
                    ).trim().toInteger() > 0
                    
                    if (hasPreviousVersion) {
                        echo "Previous version found - performing detailed comparison"
                        
                        sh '''
                            echo "=== Notepad++ Version Comparison Report ===" > "${DIFF_LOG}"
                            echo "Generated: $(date)" >> "${DIFF_LOG}"
                            echo "" >> "${DIFF_LOG}"
                            
                            echo "Previous version file count:" >> "${DIFF_LOG}"
                            find "${PREVIOUS_DIR}" -type f | wc -l >> "${DIFF_LOG}"
                            
                            echo "Current version file count:" >> "${DIFF_LOG}"
                            find "${CURRENT_DIR}" -type f | wc -l >> "${DIFF_LOG}"
                            
                            echo "" >> "${DIFF_LOG}"
                            echo "=== File Structure Analysis ===" >> "${DIFF_LOG}"
                        '''
                        
                        def diffResult = sh(
                            script: '''
                                set +e
                                
                                # Perform recursive diff and capture output
                                diff -r "${PREVIOUS_DIR}" "${CURRENT_DIR}" >> "${DIFF_LOG}" 2>&1
                                diff_status=$?
                                
                                echo "" >> "${DIFF_LOG}"
                                echo "=== Comparison Summary ===" >> "${DIFF_LOG}"
                                
                                if [ $diff_status -eq 0 ]; then
                                    echo "Result: No differences detected between versions" >> "${DIFF_LOG}"
                                    echo "NO_CHANGE"
                                elif [ $diff_status -eq 1 ]; then
                                    echo "Result: Differences found between versions" >> "${DIFF_LOG}"
                                    echo "CHANGED"
                                else
                                    echo "Result: Comparison encountered errors (status: $diff_status)" >> "${DIFF_LOG}"
                                    echo "ERROR"
                                fi
                            ''',
                            returnStdout: true
                        ).trim()
                        
                        echo "Comparison result: ${diffResult}"
                        versionChanged = (diffResult == "CHANGED")
                        
                    } else {
                        echo "No previous version available - treating as initial setup"
                        versionChanged = true
                        
                        sh '''
                            echo "=== Initial Version Setup ===" > "${DIFF_LOG}"
                            echo "Generated: $(date)" >> "${DIFF_LOG}"
                            echo "" >> "${DIFF_LOG}"
                            echo "This is the first execution of the monitoring pipeline." >> "${DIFF_LOG}"
                            echo "No previous version exists for comparison." >> "${DIFF_LOG}"
                            echo "" >> "${DIFF_LOG}"
                            echo "Current version details:" >> "${DIFF_LOG}"
                            find "${CURRENT_DIR}" -type f | sort >> "${DIFF_LOG}"
                        '''
                    }
                    
                    env.VERSION_HAS_CHANGED = versionChanged.toString()
                    echo "Version change detected: ${env.VERSION_HAS_CHANGED}"
                }
            }
        }
        
        stage('Process Version Change') {
            when {
                allOf {
                    not { equals expected: 'SUCCESS', actual: currentBuild.result }
                    expression { return env.VERSION_HAS_CHANGED == 'true' }
                }
            }
            
            steps {
                script {
                    echo "Processing detected version change"
                    
                    if (env.SKIP_LOCK_CREATION == 'true') {
                        echo "Lock file was aged - removing it and preparing for immediate notification"
                        sh "rm -f '${env.LOCK_FILE}'"
                        env.SHOULD_NOTIFY = 'true'
                    } else {
                        echo "Creating new lock file for 15-day monitoring period"
                        sh '''
                            cat > "${LOCK_FILE}" << EOF
Notepad++ Version Monitor Lock File
Created: $(date)
Purpose: Track notification timing for version changes
Next notification: $(date -d "+15 days" 2>/dev/null || date -v+15d 2>/dev/null || echo "15 days from creation")

This file prevents immediate notifications and enforces the 15-day waiting period.
EOF
                        '''
                        echo "Lock file created - notification scheduled for 15 days from now"
                    }
                    
                    // Update the previous version directory for next comparison
                    sh '''
                        echo "Updating baseline version for future comparisons"
                        rm -rf "${PREVIOUS_DIR}"
                        cp -r "${CURRENT_DIR}" "${PREVIOUS_DIR}"
                        echo "Baseline update completed"
                    '''
                }
            }
        }
        
        stage('Send Notification') {
            when {
                allOf {
                    not { equals expected: 'SUCCESS', actual: currentBuild.result }
                    expression { return env.SHOULD_NOTIFY == 'true' }
                    expression { return env.VERSION_HAS_CHANGED == 'true' }
                }
            }
            
            steps {
                script {
                    echo "Preparing and sending update notification"
                    
                    // Create detailed email content
                    sh '''
                        cat > "${TEMP_DIR}/notification_email.txt" << EOF
Subject: Notepad++ Portable Update Available

A new version of Notepad++ Portable has been detected and is ready for review.

Update Information:
- Detection Time: $(date)
- Jenkins Job: ${JOB_NAME} (Build #${BUILD_NUMBER})
- Build Details: ${BUILD_URL}

Change Analysis:
$(cat "${DIFF_LOG}")

Action Required:
Please review the detected changes and proceed with updating your Notepad++ installations as needed.

This notification was automatically generated after the 15-day monitoring period.
The system will continue monitoring for future updates.

Technical Details:
- Pipeline executed on: $(hostname)
- Workspace: ${WORKSPACE}
- Source URL: ${NOTEPAD_URL}

---
Automated notification from Jenkins Pipeline
EOF
                    '''
                    
                    // Attempt to send via system mailx if available
                    sh '''
                        if command -v mailx >/dev/null 2>&1; then
                            echo "Sending notification via mailx command"
                            mailx -s "Notepad++ Update Available" \
                                  -r "${EMAIL_FROM}" \
                                  "${EMAIL_TO}" < "${TEMP_DIR}/notification_email.txt"
                            if [ $? -eq 0 ]; then
                                echo "Email sent successfully via mailx"
                            else
                                echo "Warning: mailx command failed, will try Jenkins email"
                            fi
                        else
                            echo "mailx not available on this system, using Jenkins email only"
                        fi
                    '''
                    
                    // Also send through Jenkins emailext plugin
                    try {
                        def emailBody = readFile("${env.TEMP_DIR}/notification_email.txt")
                        emailext (
                            subject: "Notepad++ Portable Update Available",
                            body: emailBody,
                            to: env.EMAIL_TO,
                            from: env.EMAIL_FROM,
                            attachLog: true
                        )
                        echo "Notification sent via Jenkins email plugin"
                    } catch (Exception e) {
                        echo "Jenkins email plugin not available or failed: ${e.message}"
                        echo "Email content has been saved to workspace for manual review"
                    }
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "Starting pipeline cleanup phase"
                
                // Clean up temporary directories but preserve important files
                sh '''
                    echo "Removing temporary download and processing directories"
                    rm -rf "${DOWNLOAD_DIR}"
                    rm -rf "${TEMP_DIR}"
                    rm -rf "${CURRENT_DIR}"
                    
                    echo "Preserved files for next execution:"
                    if [ -f "${LOCK_FILE}" ]; then
                        echo "- Lock file: ${LOCK_FILE}"
                        echo "  Size: $(wc -c < "${LOCK_FILE}") bytes"
                    fi
                    
                    if [ -d "${PREVIOUS_DIR}" ] && [ "$(ls -A "${PREVIOUS_DIR}")" ]; then
                        file_count=$(find "${PREVIOUS_DIR}" -type f | wc -l)
                        echo "- Previous version: ${PREVIOUS_DIR} (${file_count} files)"
                    fi
                    
                    if [ -f "${DIFF_LOG}" ]; then
                        echo "- Comparison log: ${DIFF_LOG}"
                        echo "  Size: $(wc -c < "${DIFF_LOG}") bytes"
                    fi
                '''
                
                echo "Cleanup completed successfully"
            }
        }
        
        success {
            echo "Notepad++ monitoring pipeline completed successfully"
        }
        
        failure {
            script {
                echo "Pipeline execution failed"
                
                // Send failure notification if possible
                try {
                    emailext (
                        subject: "Jenkins Pipeline Failure: Notepad++ Monitor",
                        body: """
The Notepad++ monitoring pipeline encountered a failure during execution.

Job: ${env.JOB_NAME}
Build: ${env.BUILD_NUMBER}
Failure Time: ${new Date()}
Build URL: ${env.BUILD_URL}

Please check the Jenkins console logs for detailed error information.
""",
                        to: env.EMAIL_TO
                    )
                } catch (Exception e) {
                    echo "Could not send failure notification: ${e.message}"
                }
            }
        }
        
        aborted {
            echo "Pipeline execution was manually aborted or timed out"
        }
    }
}