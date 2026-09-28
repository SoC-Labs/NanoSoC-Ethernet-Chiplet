#-----------------------------------------------------------------------------
# cpu_ss_hsel / eth_ss defect on the rc4-lineage eth chiplet SoC. See README.md.
#   make soc        full-SoC, shipped RTL (must SHOW the defect) + gated control (must be clean)
#   make dma-issue  the DMA-250's own idle cycles at port switches (unit level)
# NANOSOC_MULTICORE_HOME defaults to ../../nanosoc-multicore-system; point it at a populated
# checkout when running from a worktree.
#-----------------------------------------------------------------------------
include env.mk
.PHONY: all soc soc-shipped soc-gated dma-issue variants clean
all: soc dma-issue
soc: soc-shipped soc-gated
variants:
	python3 gen_variants.py
soc-shipped: variants
	$(MAKE) -f cocotb.mk VARIANT=shipped EXPECT=defect
soc-gated: variants
	$(MAKE) -f cocotb.mk VARIANT=gated EXPECT=clean
dma-issue:
	$(MAKE) -C dma_issue
clean:
	rm -rf build results_*.xml *.log ucli.key __pycache__
	$(MAKE) -C dma_issue clean
.PHONY: env
env:
	@echo "NANOSOC_MULTICORE_HOME   = $(NANOSOC_MULTICORE_HOME)"
	@echo "ARM_IP_LIBRARY_PATH      = $(ARM_IP_LIBRARY_PATH)"
	@echo "CMSDK_DIR                = $(CMSDK_DIR)"
	@echo "ARM_CORTEXM0PLUS_IP_PATH = $(ARM_CORTEXM0PLUS_IP_PATH)"
