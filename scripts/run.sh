#!/usr/bin/env bash
# Git Actions runner launcher — reads the GIT_* env contract, registers the runner
# against the configured instance, then execs the daemon. act_runner takes
# --instance/--token/--name as CLI flags, so the binary is untouched; this only
# maps env -> flags. White-label branding (e.g. "Hanzo Git") is applied by the
# server, never baked into this binary.
set -o pipefail
[[ -d /data ]] || mkdir -p /data
cd /data
RUNNER_STATE_FILE=${RUNNER_STATE_FILE:-'.runner'}

CONFIG_ARG=""; [[ -n "${CONFIG_FILE}" ]] && CONFIG_ARG="--config ${CONFIG_FILE}"
EXTRA_ARGS=""
[[ -n "${GIT_RUNNER_LABELS}" ]]    && EXTRA_ARGS="${EXTRA_ARGS} --labels ${GIT_RUNNER_LABELS}"
[[ -n "${GIT_RUNNER_EPHEMERAL}" ]] && EXTRA_ARGS="${EXTRA_ARGS} --ephemeral"
RUN_ARGS=""
[[ -n "${GIT_RUNNER_ONCE}" ]]      && RUN_ARGS="${RUN_ARGS} --once"

# Token may be supplied via a *_FILE (docker/k8s secret) instead of the env.
if [[ -z "${GIT_RUNNER_TOKEN}" ]] && [[ -f "${GIT_RUNNER_TOKEN_FILE}" ]]; then
  GIT_RUNNER_TOKEN="$(cat "${GIT_RUNNER_TOKEN_FILE}")"
fi

if [[ ! -s "$RUNNER_STATE_FILE" ]]; then
  try=0; success=0
  # Wait a moment for the server to become available before erroring out — handy
  # when runner and server come up together (e.g. one docker-compose).
  while [[ $success -eq 0 ]] && [[ $try -lt ${GIT_MAX_REG_ATTEMPTS:-10} ]]; do
    try=$((try + 1))
    git-runner register \
      --instance "${GIT_INSTANCE_URL}" \
      --token    "${GIT_RUNNER_TOKEN}" \
      --name     "${GIT_RUNNER_NAME:-$(hostname)}" \
      ${CONFIG_ARG} ${EXTRA_ARGS} --no-interactive 2>&1 | tee /tmp/reg.log
    if grep -q 'registered successfully' /tmp/reg.log; then echo "SUCCESS"; success=1; else echo "Waiting to retry ..."; sleep 5; fi
  done
fi
unset GIT_RUNNER_TOKEN GIT_RUNNER_TOKEN_FILE
exec git-runner daemon ${CONFIG_ARG} ${RUN_ARGS}
