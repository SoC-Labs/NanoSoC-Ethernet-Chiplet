# FIXTURE, not the real ASIC/common.mk — see ci/fixtures/README.md.
.PHONY: rom-vars
rom-vars:
	@echo 'eth|eth_rom|_fixture/romlibs/eth_rom|_fixture/fw/eth_ss_bootrom.bintxt|_fixture/romlibs/eth_rom/eth_rom_via.memlib|eth_rom_via|build/rom_verify/eth.json|build/rom_verify/eth_gds.bits'
