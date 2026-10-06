#!/bin/sh
# Orbit CLI 빌드 게이트 — 기타 CI, CI 없는 환경용 셸 스크립트 샘플
#
# CircleCI, Buildkite, Drone, TeamCity 등 자동 인식 대상이 아닌 CI와 수동 빌드에서 씁니다.
# 실제 파이프라인에 적용하는 템플릿입니다.
#   빌드 → 태그 → scan image → push → scan promote
# 각 구간은 서로의 결과 변수에 기대지 않습니다. 필요 없는 구간은 지워도 나머지가 동작합니다.
# 단, 빌드·태그는 판정할 이미지를 만드는 구간이라 scan image·push·promote를 쓰는 동안 남겨 둡니다.
#
# 필요한 환경변수(CI의 비밀 저장소에서 주입):
#   ORBIT_CLIENT_ID, ORBIT_CLIENT_SECRET
#   REGISTRY_USERNAME, REGISTRY_TOKEN — REGISTRY_LOGIN이 credentials일 때만
set -eu

# ─── 여기만 바꿉니다 ─────────────────────────────────────────────────────
# 같은 이름의 환경변수를 주면 그 값을 씁니다.
# 판정하고 올릴 이미지. 예: registry.example.com/team/myapp
# 첫 부분(registry.example.com)이 레지스트리 주소이며, push와 로그인 모두 이 주소로 갑니다.
# 시연: ttl.sh/orbit/orbit-gate-hello-<임의 문자열> + IMAGE_TAG=1h (자격 불필요, 공개됨)
IMAGE="${IMAGE:-<레지스트리>/<네임스페이스>/<이름>}"
# 비우면 커밋 해시를 태그로 씁니다.
IMAGE_TAG="${IMAGE_TAG:-}"
# 레지스트리 로그인. 둘 중 하나를 반드시 적습니다. 정하지 않으면 push에서 멈춥니다.
#   credentials : 환경변수 REGISTRY_USERNAME, REGISTRY_TOKEN으로 로그인합니다.
#   none        : 로그인하지 않습니다. ttl.sh나 이미 로그인된 기계일 때만 씁니다.
REGISTRY_LOGIN="${REGISTRY_LOGIN:-<credentials 또는 none>}"
# 파이프라인 식별값. {호스트}/{프로젝트 경로}/{파이프라인 정의} 형태의 고정값. 예: circleci.com/example/myapp/build
PIPELINE_REF="${PIPELINE_REF:-<호스트>/<프로젝트 경로>/<파이프라인 정의>}"
# 소스 저장소 좌표. 예: github.com/example/myapp
SOURCE_REF="${SOURCE_REF:-<소스 저장소 좌표>}"
# 실행마다 달라지는 값. CI의 실행 번호를 넘깁니다(예: CircleCI는 $CIRCLE_BUILD_NUM). 없으면 실행 시각
CI_RUN_ID="${CI_RUN_ID:-local-$(date +%Y%m%d%H%M%S)}"
# ─────────────────────────────────────────────────────────────────────────

CANDIDATE_IMAGE='orbit-gate-candidate:local'
# CLI 2.0.1에 digest로 고정되어 있습니다. 다른 버전은 README 참고
ORBIT_CLI_IMAGE='ghcr.io/oliveworks-io/orbit-cli:2.0.1@sha256:ce55fd53b389998ee2fa125ca6e5baf944384c1f9c56f5ff2c8e9bbe1e6aceca'
GIT_COMMIT="$(git rev-parse HEAD)"
GATE_REF="$IMAGE:${IMAGE_TAG:-$GIT_COMMIT}"

# 1) 푸시하지 않고 로컬에만 적재합니다.
docker build -t "$CANDIDATE_IMAGE" .

# 2) 최종 이미지 참조를 붙입니다(푸시 아님). IMAGE를 설정하지 않았으면 여기서 멈춥니다.
case "$IMAGE" in
  ''|*'<'*) echo "IMAGE를 설정하십시오. 예: registry.example.com/team/myapp / 시연: ttl.sh/orbit/orbit-gate-hello-<임의 문자열> (IMAGE_TAG=1h)"; exit 1 ;;
esac
docker tag "$CANDIDATE_IMAGE" "$GATE_REF"

# 3) 판정. 통과가 아닌 모든 경우(차단, 오류)에 중단합니다. 빌드 좌표를 설정하지 않았으면 여기서 멈춥니다.
case "$PIPELINE_REF$SOURCE_REF" in
  *'<'*) echo "PIPELINE_REF와 SOURCE_REF를 설정하십시오. 예: circleci.com/example/myapp/build, github.com/example/myapp"; exit 1 ;;
esac
SOCK_GID="$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  alpine:3 stat -c '%g' /var/run/docker.sock)"
# 플랫폼(아키텍처)을 손으로 적지 않습니다. 빌드는 이 기계의 아키텍처로 만들어집니다.
PLATFORM="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$GATE_REF")"
set +e
docker run --rm \
  -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET \
  --group-add "$SOCK_GID" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$ORBIT_CLI_IMAGE" \
  scan image "$GATE_REF" \
    --pipeline-ref "$PIPELINE_REF" \
    --source-ref   "$SOURCE_REF" \
    --git-commit   "$GIT_COMMIT" \
    --ci-run-id    "$CI_RUN_ID" \
    --platform     "$PLATFORM" \
    --details --format json > gate.json
GATE_EXIT=$?
set -e
if [ -s gate.json ]; then cat gate.json; else echo "(판정 응답 없음)"; fi
[ "$GATE_EXIT" = "0" ] || { echo "게이트 차단/오류 (exit $GATE_EXIT)"; exit 1; }

# 4) 판정한 그 이미지를 그대로 올립니다. REGISTRY_LOGIN에 따라 로그인하고, 로그인 호스트는 IMAGE에서 뽑습니다.
case "$IMAGE" in ttl.sh/*) echo "경고: ttl.sh는 공개 임시 레지스트리입니다. 누구나 이 이미지를 받을 수 있습니다." ;; esac
case "$REGISTRY_LOGIN" in
  credentials)
    [ -n "${REGISTRY_USERNAME:-}" ] && [ -n "${REGISTRY_TOKEN:-}" ] || { echo "REGISTRY_LOGIN=credentials인데 REGISTRY_USERNAME, REGISTRY_TOKEN이 없습니다"; exit 1; }
    HOST="${IMAGE%%/*}"
    case "$HOST" in *.*|*:*|localhost) ;; *) HOST=docker.io ;; esac
    echo "$REGISTRY_TOKEN" | docker login -u "$REGISTRY_USERNAME" --password-stdin "$HOST" ;;
  none) ;;
  *) echo "REGISTRY_LOGIN을 정하십시오. 자격으로 로그인하려면 credentials, 로그인하지 않으려면 none"; exit 1 ;;
esac
docker push "$GATE_REF"

# 5) 확정 digest를 보고합니다. requestId는 gate.json에서, digest는 push된 이미지에서 직접 읽습니다.
#    앞 구간을 지워 값이 없으면 건너뜁니다.
REQUEST_ID="$(grep -o '"requestId" *: *"[^"]*"' gate.json 2>/dev/null | head -n 1 | cut -d'"' -f4 || true)"
IMAGE_DIGEST="$(docker inspect --format '{{index .RepoDigests 0}}' "$GATE_REF" 2>/dev/null | cut -d'@' -f2 || true)"
if [ -z "$REQUEST_ID" ]; then
  echo "gate.json에 requestId가 없어 보고하지 않습니다"
elif [ -z "$IMAGE_DIGEST" ]; then
  echo "push된 digest가 없어 보고하지 않습니다"
else
  docker run --rm -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET \
    "$ORBIT_CLI_IMAGE" \
    scan promote --request-id "$REQUEST_ID" --image-digest "$IMAGE_DIGEST"
fi
