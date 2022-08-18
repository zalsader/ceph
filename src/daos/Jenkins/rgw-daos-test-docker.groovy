// This file must be manually inserted into the pipeline section of the jenkins configuration
// https://eos-jenkins.colo.seagate.com/job/Release_Engineering/job/re-workspace/job/sv_space/job/rgwdaos-test-docker/configure
pipeline {
    agent {
        node {
            label "rgwdaos-node"
        }
    }

    stages {
        stage ('Build docker images, run s3-tests') {
            steps {
                script { build_stage = env.STAGE_NAME }
                sh label: 'Run DAOS-CORTX S3-Tests', script: '''
					echo $HOSTNAME
					docker images
					export ARTIFACTS_FOLDER=/opt/dev-s3-tests
                    export CEPH_PATH=/opt/ceph-test/ceph
                    export DAOS_PATH=/opt/daos
                    export S3TESTS_PATH=/opt/s3-tests
                    export CONTAINER_NAME='dgws3-test'
					sh /opt/ceph-test/ceph/src/daos/docker/test.sh --summary=true --artifacts-folder=$ARTIFACTS_FOLDER --local-artifacts=$ARTIFACTS_FOLDER --s3tests-image-name=dgw-s3-dev --update-confluence=false --build-docker-images=false --cleanup-container=false
					ls -l $ARTIFACTS_FOLDER/*.csv
					cp $ARTIFACTS_FOLDER/test_diff.csv $WORKSPACE
					cp $ARTIFACTS_FOLDER/test_output.csv $WORKSPACE
					cp $ARTIFACTS_FOLDER/test_summary.csv $WORKSPACE
                '''
                // archiveArtifacts artifacts: "*.csv", onlyIfSuccessful: false, allowEmptyArchive: true 
                script {
                    // Date,Host,ok,FAIL,ERROR,SKIP,MISSING,NOT_RUNNING,CRASHED,Total
                    RUN_DATE = "$(date +"%Y-%m-%d")"
                    LOCAL_ARTIFACTS=/opt/$RUN_DATE
                    File file = new File($LOCAL_ARTIFACTS/test_summary.csv)
                    def ( date_title, host_title, ok_title, fail_title, error_title, skip_title, missing_title, notrunning_title, crashed_title, total_title) = file.readLine()
                    def ( date_data, host_data, ok_data, fail_data, error_data, skip_data, missing_data, notrunning_data, crashed_data, total_data) = file.readLine()

                    println "date_title=${date_title}"
                    println "host_title=${host_title}"
                    println "ok_title=${ok_title}"
                    println "fail_title=${fail_title}"
                    println "error_title=${error_title}"
                    println "skip_title=${skip_title}"
                    println "missing_title=${missing_title}"
                    println "notrunning_title=${notrunning_title}"
                    println "crashed_title=${crashed_title}"
                    println "total_title=${total_title}"

                    println "date_data=${date_data}"
                    println "host_data=${host_data}"
                    println "ok_data=${ok_data}"
                    println "fail_data=${fail_data}"
                    println "error_data=${error_data}"
                    println "skip_data=${skip_data}"
                    println "missing_data=${missing_data}"
                    println "notrunning_data=${notrunning_data}"
                    println "crashed_data=${crashed_data}"
                    println "total_data=${total_data}"
                }
            }
        }
    }

    post {
        cleanup {
            sh label: 'Collect Artifacts', script: '''
				# reboot the node in 30 seconds, hugepages need to be cleared between runs
				# (sudo bash -c "(sleep 30 && sudo shutdown -r now) &") &
            '''
            script {
                // Archive Deployment artifacts in jenkins build
                // writeFile(file: '$WORKSPACE/results.html', text: ${SCRIPT, template="cluster-setup-email.template"})
                archiveArtifacts artifacts: "*"
            }
        }
        always { 
            script {
                // Email Notification
                def recipientProvidersClass = [[$class: 'RequesterRecipientProvider']]
                mailRecipients = "walter.warniaha@seagate.com"
                emailext ( 
                    body: '''${SCRIPT, template="cluster-setup-email.template"}''',
                    mimeType: 'text/html',
                    subject: "[Jenkins Build ${currentBuild.currentResult}] : ${env.JOB_NAME}",
                    attachLog: false,
                    to: "${mailRecipients}",
                    recipientProviders: recipientProvidersClass
                )
            }
        }
    }
}
