.PHONY:	all sim simall doc clean vpi
all:	vpi
	@make -C bench all
	@make -C rtl all
	@make -C rtl/fifo all
	@make -C synth all
	@make -C driver all

vpi:
	@make -C vpi all

sim:	all vpi
	@make -C bench sim
	@make -C build sim

usbsim:	vpi
	@make -C bench usbsim
	@make -C rtl sim
	@make -C build usbsim

simall:	sim vpi
	@make -C rtl sim
	@make -C rtl/fifo sim
	@make -C build sim

#
#  Build using Dockerized Gowin synthesis
##
.PHONY:	docker gowin synth flash

# Settings for building the Docker image:
UID	:= `id -u $(USER)`
GID	:= `id -g $(USER)`
ARGS	:=  --build-arg USERNAME=$(USER) --build-arg USER_UID=$(UID) --build-arg USER_GID=$(GID)

docker:
	@docker build -f Dockerfile $(ARGS) -t gowin-eda:latest .

# Settings for running Gowin synthesis within the Docker image:
USERDIR	:= /home/$(USER)/:/home/$(USER):rw
PASSWD	:= /etc/passwd:/etc/passwd:ro
GROUP	:= /etc/group:/etc/group:ro
VOLUMES	:= -v `pwd`:/build/misc-verilog-cores:rw -v $(PASSWD) -v $(GROUP) -v $(USERDIR)
TOPDIR	:= /build/misc-verilog-cores/synth/sipeed-tang-primer-20k
MAKE	:= make -f gowin.mk GW_SH=/opt/gowin/IDE/bin/gw_sh

gowin:	docker
	@docker run $(VOLUMES) -e USER=$(USER) --user=$(UID):$(GID) -w=$(TOPDIR) \
--rm -it gowin-eda bash -c "$(MAKE)"

synth:	docker
	@docker run $(VOLUMES) -e USER=$(USER) --user=$(UID):$(GID) -w=$(TOPDIR) \
--rm -it gowin-eda bash

# Build and upload (to SRAM) the USB demo:
SYNDIR	:= `pwd`/synth/sipeed-tang-primer-20k
BIT	:= $(SYNDIR)/impl/pnr/usbcore.fs
flash:	gowin
	openFPGALoader --board tangprimer20k --write-sram $(BIT)

#
#  Synthesise the USB2 + DDR3 test.
##
USBDDR	:= /build/misc-verilog-cores/synth/gowin-ddr3-test
.PHONY:	usbddr upload
usbddr:	docker
	@docker run $(VOLUMES) -e USER=$(USER) --user=$(UID):$(GID) -w=$(USBDDR) \
--rm -it gowin-eda bash -c "$(MAKE)"
	@openFPGALoader --board tangprimer20k --write-sram synth/gowin-ddr3-test/impl/pnr/project.fs

# Note: writing to Flash does not work for me, on Gowin GW2A.
erase:
	@openFPGALoader --board tangprimer20k --unprotect-flash --bulk-erase

#
#  Synthesise the USB2 + DDR3 test.
##
USBTOP	:= /build/misc-verilog-cores/synth/sipeed-tang-primer-20k
.PHONY:	usbtop
usbtop:	docker
	@docker run $(VOLUMES) -e USER=$(USER) --user=$(UID):$(GID) -w=$(USBTOP) \
--rm -it gowin-eda bash -c "$(MAKE)"
	@openFPGALoader --board tangprimer20k --write-sram synth/sipeed-tang-primer-20k/impl/pnr/project.fs

#
#  Documentation settings
##

# Source Markdown files and PDF outputs:
MD	:= $(wildcard *.md)
DOC	:= $(filter-out %.inc.md, $(MD))
PDF	:= $(DOC:.md=.pdf)

# Include-files:
INC	:= $(filter %.inc.md, $(MD))
TMP	?= doc/cores.latex
CLS	?= doc/coresreport.cls

# Images:
PNG	:= $(wildcard doc/images/*.png)
SVG	:= $(wildcard doc/images/*.svg)
DOT	:= $(wildcard doc/images/*.dot)
PIC	:= $(SVG:.svg=.pdf) $(DOT:.dot=.pdf)

# Pandoc settings:
FLT	?= --citeproc
# FLT	?= --filter=pandoc-include --filter=pandoc-fignos --filter=pandoc-citeproc
#OPT	?= --number-sections --bibliography=$(REF)
OPT	?= --number-sections

doc:	$(PDF) $(PIC) $(PNG) $(INC)

clean:
	@make -C bench clean
	@make -C build clean
	@make -C driver clean
	@make -C rtl clean
	@make -C vpi clean
	@make -C synth clean
	rm -f $(PDF) $(LTX) $(PIC)

# Implicit rules:
%.pdf: %.md $(PIC) $(PNG) $(TMP) $(INC)
	+pandoc --template=$(TMP) $(FLT) $(OPT) -f markdown+tex_math_double_backslash -t latex -V papersize:a4 -V geometry:margin=2cm $< -o $@

%.tex: %.md $(PIC) $(PNG) $(TMP)
	+pandoc --filter=pandoc-fignos --filter=pandoc-citeproc --bibliography=$(REF) \
		-f markdown+tex_math_double_backslash -t latex $< -o $@

%.pdf: %.svg
	+inkscape --export-area-drawing --export-text-to-path --export-pdf=$@ $<

%.pdf: %.dot
	+dot -Tpdf -o$@ $<

%.pdf: %.eps
	+inkscape --export-area-drawing --export-text-to-path --export-pdf=$@ $<