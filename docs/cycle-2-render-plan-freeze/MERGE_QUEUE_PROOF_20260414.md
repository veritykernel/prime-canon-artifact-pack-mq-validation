# Merge queue proof receipt

source_repo: joeyeoj69/prime-canon-artifact-pack
source_branch: cycle-2/render-plan-freeze

validation_repo: veritykernel/prime-canon-artifact-pack-mq-20260414053437
validation_repo_ruleset_id: 15040134
validation_repo_ruleset_name: required-ci-publish-guard-main-mq

required_check_context: publish-guard-check
proof_pr_number: 1
proof_pr_url: https://github.com/veritykernel/prime-canon-artifact-pack-mq-20260414053437/pull/1
merge_group_run_url: https://github.com/veritykernel/prime-canon-artifact-pack-mq-20260414053437/actions/runs/24382822268

proof_result: success

validated_surfaces:
- push
- pull_request
- merge_group

notes:
- main push workflow completed successfully
- proof branch push workflow completed successfully
- pull_request workflow completed successfully
- merge queue accepted deterministic enqueue
- merge_group workflow completed successfully
