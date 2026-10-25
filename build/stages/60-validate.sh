# Stage 60 — validate the sealed image structure and contents.
stage_60_validate() {
  step "Validating image structure"
  python3 "${PROJECT_DIR}/tests/image/validate_image.py" --image "$WORK_IMG" \
    2>&1 | tee -a "$BUILD_LOG"
  local rc=${PIPESTATUS[0]}
  (( rc == 0 )) || die "image validation failed"
  ok "image validation passed"
}
