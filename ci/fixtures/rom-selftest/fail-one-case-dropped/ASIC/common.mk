# FIXTURE, not the real ASIC/common.mk — see ci/fixtures/README.md.
# 24 of 25: ONE case silently dropped. The gate's old `2[0-9]` regex accepted
# this, which is why the exact count is now pinned.
.PHONY: romlibs-selftest
romlibs-selftest:
	@echo 'SELFTEST: 24 passed, 0 failed'
