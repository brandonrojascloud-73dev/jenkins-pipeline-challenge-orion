# Notepad++ Version Monitor Pipeline

This Jenkins pipeline automates the monitoring of Notepad++ Portable releases and handles notifications with a smart delay mechanism. I built this to solve the challenge of tracking software updates while avoiding notification spam.

## What This Does

The pipeline downloads the latest Notepad++ Portable release, compares it against the previous version, and manages a 15-day notification delay system. When changes are detected, it either creates a lock file to start the waiting period or sends an email notification if the waiting period has elapsed.

I designed this with real-world usage in mind - nobody wants to get bombarded with update notifications every time the pipeline runs, so the lock file mechanism ensures you only get notified when it actually matters.

## How It Works

The pipeline runs through six main stages that handle everything from initial setup to cleanup. Here's the flow I implemented:

**Setup Workspace** - Creates all the necessary directories and prepares the environment. Nothing fancy here, just good housekeeping.

**Evaluate Lock Status** - This is where the intelligence happens. The pipeline checks if a lock file exists and calculates its age. If it's been 15 days or more since the lock was created, we proceed with notification. If it's newer than that, we exit early to avoid unnecessary work.

**Download Current Version** - Downloads the latest Notepad++ Portable with robust error handling. I included multiple retry attempts because network issues happen, and the pipeline needs to handle them gracefully.

**Compare With Previous** - Performs a thorough comparison between the current download and the previous version. This uses both file-based diff operations and hash comparisons to catch any changes.

**Process Version Change** - Handles the lock file logic and updates the baseline version for future comparisons. This is where we decide whether to create a new lock file or remove an old one.

**Send Notification** - Sends detailed email notifications using both system mailx and Jenkins email plugins for maximum reliability.

## The Lock File Approach

I chose a file-based locking mechanism because it's simple and reliable. When the pipeline detects a version change for the first time, it creates a lock file with a timestamp. On subsequent runs, it checks the age of this file.

The lock file contains basic metadata about when it was created and why, which helps with debugging and understanding the system state. I made sure the age calculation works on both Linux and macOS since different systems handle the `stat` command differently.

If no previous version exists (first run), the pipeline treats everything as new but still follows the same lock file logic for consistency.

## Download Strategy

Downloading files reliably over the internet requires handling various failure scenarios. I implemented a retry mechanism with exponential backoff and comprehensive validation.

The download process includes file size validation because a tiny download probably means something went wrong. I also verify that the downloaded file is actually a valid ZIP archive before proceeding with extraction.

Timeout handling happens at multiple levels - both at the pipeline stage level and within the curl command itself. This prevents the pipeline from hanging indefinitely if something goes wrong.

## Version Comparison Logic

Comparing software versions isn't just about checking if files are identical. I implemented a multi-layered approach that looks at file counts, directory structure, content differences, and hash comparisons.

The comparison generates a detailed report that gets included in email notifications. This gives administrators actual useful information about what changed, not just "something is different."

I included both diff-based and hash-based comparison methods because they catch different types of changes. The diff approach is great for seeing structural changes, while hash comparison catches subtle content modifications.

## Email Notifications

For email delivery, I implemented dual paths to maximize reliability. The primary method uses the system's mailx command, with Jenkins emailext as a fallback.

The notification emails include comprehensive information: what changed, when it was detected, build details for traceability, and the full comparison report. I tried to make them actually useful rather than just "hey, something happened."

## File Organization

I kept the structure simple but organized:

```
Jenkinsfile - The main pipeline definition
scripts/download_utils.sh - Handles downloading and extraction
scripts/version_compare.sh - Version comparison logic
README.md - This documentation
```

The helper scripts can be run independently, which makes testing and debugging much easier. I hate when pipeline logic is all embedded in Groovy and impossible to test outside Jenkins.

## Configuration and Setup

The pipeline uses environment variables for configuration, which keeps the important settings visible and easy to modify. The main things you'll want to adjust are the email addresses and possibly the download URL if Notepad++ changes their release structure.

For Jenkins setup, create a pipeline job pointing to this repository. Make sure your Jenkins agent has the basic Unix tools available - curl, unzip, diff, and optionally mailx for email.

I recommend running this on a daily schedule, something like 2 AM when it won't interfere with other work.

## Design Decisions I Made

I chose declarative pipeline syntax because it provides better structure and built-in error handling compared to scripted pipelines. The stage-based approach makes it easier to understand what's happening and debug when things go wrong.

The lock file mechanism uses file modification timestamps rather than storing dates in the file content. This is more reliable because it works regardless of file content and survives system clock changes better.

For the comparison logic, I decided to preserve both the current and previous versions instead of just keeping hashes. This uses more disk space but provides much better debugging capability when you need to understand what actually changed.

Error handling follows a "fail fast" philosophy for critical errors but includes graceful degradation where possible. For example, if mailx isn't available, the pipeline continues and tries the Jenkins email plugin instead.

## Idempotency and Safety

The pipeline can be run multiple times safely without causing problems. It cleans up after itself and maintains consistent state between runs.

I included several safety measures: concurrent builds are disabled to prevent race conditions, timeouts prevent hung processes, and comprehensive cleanup ensures temporary files don't accumulate over time.

The lock file mechanism itself prevents duplicate notifications, which was a key requirement.

## Monitoring and Troubleshooting

When monitoring this pipeline, watch for a few key patterns in the logs. "Lock file exceeds 15 day threshold" means a notification will be sent. "Download failed after multiple retry attempts" usually indicates network issues or changes to the Notepad++ release URL.

For troubleshooting, the most common issues are network connectivity problems and email configuration issues. The pipeline provides detailed logging to help identify what's going wrong.

If you need more verbose output for debugging, you can temporarily enable timestamps in the pipeline options.

## Assumptions and Constraints

This solution assumes you're running on a Unix-like system with standard command-line tools available. It needs network access to download files and sufficient disk space for the downloads and extractions.

The email functionality requires either a working mailx installation or proper Jenkins email plugin configuration. The pipeline will work without email, but you won't get notifications.

The 15-day threshold is hardcoded but could easily be made configurable if needed.

## What Could Be Improved

In a production environment, I'd probably add configuration management to externalize more settings. Integration with a proper artifact repository would be nice for version history.

Webhook-based triggering instead of polling would be more efficient, though it would require changes to how Notepad++ publishes releases.

For larger organizations, integration with Slack or Teams might be more useful than email notifications.

Overall, this solution addresses the core requirements while remaining maintainable and debuggable. The modular design makes it easy to extend or modify for different use cases.
Test-challenge
