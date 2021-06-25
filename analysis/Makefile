include ../Makevars

OUTPUT_DIR := $(RUN_DIR)/analysis

define RMD
	-@mkdir -p $(OUTPUT_DIR)
	$(call LOG,RENDERING $(1).Rmd into $(2).html)
	$(R) --quiet --no-save -e 'rmarkdown::render("$(1).Rmd", output_file="$(OUTPUT_DIR)/$(2).html", params=list(base_dir="$(3)", output_dir="$(OUTPUT_DIR)"))'

endef

.PHONY: all
all: base package kaggle

.PHONY: base
base:
	$(call RMD,usage,base-usage,$(PREPROCESS_DIR)/base)

.PHONY: kaggle
kaggle:
	$(call RMD,usage,kaggle-usage,$(PREPROCESS_DIR)/kaggle)

.PHONY: package
package: corpus normalized side-effects environments provenance
	$(call RMD,usage,package-usage,$(PREPROCESS_DIR)/package)

.PHONY: corpus
corpus:
	$(call RMD,corpus,corpus,$(PREPROCESS_DIR))

.PHONY: normalized
normalized:
	$(call RMD,normalized,normalized,$(PREPROCESS_DIR)/package)

.PHONY: side-effects
side-effects:
	$(call RMD,side-effects,side-effects,$(PREPROCESS_DIR))


.PHONY: environments
environments:
	$(call RMD,environments,environments,$(PREPROCESS_DIR)/package)

.PHONY: provenance
provenance:
	$(call RMD,provenance,provenance,$(PREPROCESS_DIR)/package)