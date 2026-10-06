# orbit-gate-hello — 빌드 게이트 시연용 이미지. 앱 소스가 없습니다.
#
# 이 이미지에는 취약점이 알려진 라이브러리가 하나 들어 있지만, 그 라이브러리를 실행하는 경로는 없습니다.
#   - 들어 있는 것: Apache Commons Text 1.9 (CVE-2022-42889, "Text4Shell")
#   - 실행 경로가 없는 이유: JRE가 없고, 어떤 프로세스의 클래스패스에도 올라가지 않습니다.
#     CVE-2022-42889는 앱이 StringSubstitutor 보간을 외부 입력에 적용해야 악용됩니다.
# SBOM에는 이 라이브러리가 잡히므로, 게이트가 "실행되지 않는 의존성"을 어떻게 판정하는지 볼 수 있습니다.
# 판정(통과/차단)은 조직의 게이트 정책이 정합니다.
#
# 운영 이미지의 예가 아닙니다. 시연·시험 용도로만 씁니다.

# 베이스는 알려진 취약점이 거의 없는 Wolfi로 둡니다. 판정에서 위 라이브러리만 두드러지게 하기 위해서입니다.
# 패키지 DB가 있어 SBOM이 비지 않습니다(빈 SBOM은 CLI가 종료 코드 2로 중단합니다).
# 같은 결과를 재현하도록 digest로 고정합니다.
FROM cgr.dev/chainguard/wolfi-base@sha256:00fd4e9cdd9c5576c336d979fa663f9976f160c456b6ae9fe87e19c4e9c759a2

LABEL org.opencontainers.image.title="orbit-gate-hello" \
      org.opencontainers.image.description="Orbit build gate demo image: vulnerable but unreachable dependency" \
      org.opencontainers.image.source="https://github.com/oliveworks-io/orbit-cli-examples"

# JAR은 저장소의 vendor/에 들어 있어 빌드 중에 Maven Central에 접속하지 않습니다.
# Maven Central 공개 SHA-1(ba6ac8c2…e80e2)과 대조해 확인한 파일의 SHA-256입니다.
ARG COMMONS_TEXT_SHA256=0812f284ac5dd0d617461d9a2ab6ac6811137f25122dfffd4788a4871e732d00

# 저장소의 파일이 바뀌었으면 빌드를 실패시킵니다.
COPY vendor/commons-text-1.9.jar /opt/orbit-gate-hello/lib/commons-text-1.9.jar
RUN echo "${COMMONS_TEXT_SHA256}  /opt/orbit-gate-hello/lib/commons-text-1.9.jar" | sha256sum -c - \
 && chmod 0644 /opt/orbit-gate-hello/lib/commons-text-1.9.jar

USER 65532:65532
CMD ["sh", "-c", "echo 'orbit-gate-hello'; sleep infinity"]
