#!/bin/sh
# Orbit CLI 빌드 게이트 — 기타 CI, CI 없는 환경용 셸 스크립트 샘플
#
# CircleCI, Buildkite, Drone, TeamCity 등 자동 인식 대상이 아닌 CI와 수동 빌드에서 씁니다.
# 사용 전에 아래 값을 환경에 맞게 바꿉니다.
#   IMAGE            : 배포할 이미지 이름(레지스트리 포함)
#   ORBIT_CLI_IMAGE  : <64자 hex> 자리에 확인한 digest를 넣습니다.
#   PIPELINE_REF     : {호스트}/{프로젝트 경로}/{파이프라인 정의} 형태의 고정값
#   SOURCE_REF       : 소스 저장소 좌표
# 필요한 환경변수: ORBIT_CLIENT_ID, ORBIT_CLIENT_SECRET (CI의 비밀 저장소에서 주입)
set -eu

IMAGE='registry.example.com/team/myapp'
CANDIDATE_IMAGE='myapp:candidate'
ORBIT_CLI_IMAGE='ghcr.io/oliveworks-io/orbit-cli:2.0.0@sha256:<64자 hex>'
PIPELINE_REF="circleci.com/example/myapp/build"
SOURCE_REF="github.com/example/myapp"

# 1) 푸시하지 않고 로컬에만 적재합니다.
docker build -t "$CANDIDATE_IMAGE" .

# 2) 최종 이미지 참조를 붙입니다(푸시 아님).
GATE_REF="$IMAGE:$(git rev-parse --short HEAD)"
docker tag "$CANDIDATE_IMAGE" "$GATE_REF"

# 3) 판정을 받습니다.
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
    --git-commit   "$(git rev-parse HEAD)" \
    --ci-run-id    "${CI_BUILD_NUM:-local-$$}" \
    --platform     "$PLATFORM" \
    --details --format json > gate.json
GATE_EXIT=$?
set -e

if [ -s gate.json ]; then cat gate.json; else echo "(판정 응답 없음)"; fi

# 4) 통과가 아니면 중단합니다. 오류(2)도 통과가 아닙니다.
[ "$GATE_EXIT" = "0" ] || { echo "게이트 차단/오류 (exit $GATE_EXIT)"; exit 1; }

# 5) 판정한 그 이미지를 그대로 올립니다.
docker push "$GATE_REF"

# 6) 선택: 확정된 digest를 보고해 런타임 이미지와 연결합니다.
REQUEST_ID="$(grep -o '"requestId" *: *"[^"]*"' gate.json | head -n 1 | cut -d'"' -f4 || true)"
IMAGE_DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "$GATE_REF" | cut -d'@' -f2)"
if [ -n "$REQUEST_ID" ] && [ -n "$IMAGE_DIGEST" ]; then
  docker run --rm \
    -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET \
    "$ORBIT_CLI_IMAGE" \
    scan promote --request-id "$REQUEST_ID" --image-digest "$IMAGE_DIGEST"
else
  echo "requestId 또는 digest를 확인하지 못해 보고하지 않습니다"
fi
