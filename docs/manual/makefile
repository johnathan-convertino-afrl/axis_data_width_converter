PROJECT_NAME := axis_data_width_converter

MK_DIR := makefiles

export PROJECT_NAME

.PHONY: clean GEN_FUSESOC_CORE_LATEX FUSSOC_CORE_LATEX_CLEAN GEN_HTML HTML_CLEAN GEN_PDF PDF_CLEAN

all: GEN_FUSESOC_CORE_LATEX GEN_HTML GEN_PDF

GEN_FUSESOC_CORE_LATEX:
	$(MAKE) -f $(MK_DIR)/makefuselatex.mk

GEN_HTML:
	$(MAKE) -f $(MK_DIR)/makehtml.mk

GEN_PDF: GEN_HTML
	$(MAKE) -f $(MK_DIR)/makepdf.mk

clean: FUSSOC_CORE_LATEX_CLEAN HTML_CLEAN PDF_CLEAN

FUSSOC_CORE_LATEX_CLEAN:
	$(MAKE) -f $(MK_DIR)/makefuselatex.mk clean

HTML_CLEAN:
	$(MAKE) -f $(MK_DIR)/makehtml.mk clean

PDF_CLEAN:
	$(MAKE) -f $(MK_DIR)/makepdf.mk clean

