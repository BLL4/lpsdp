UNAME_S := $(shell uname -s)

CC := "g++"

# This is some attempt to locate GUROBI and MOSEK installations
# It may be best to hardcode these paths if the automatic detection fails

GUROBI_HOME ?= $(shell echo $$GUROBI_HOME)
ifeq ($(GUROBI_HOME),)
  GUROBI_BIN := $(shell which gurobi_cl 2>/dev/null)
  ifneq ($(GUROBI_BIN),)
    #GUROBI_HOME := $(dir $(dir $(GUROBI_BIN)))
    GUROBI_HOME := $(shell dirname $$(dirname $$(realpath $$(which gurobi_cl 2>/dev/null))) )
  endif
endif

MOSEK_HOME ?= $(shell echo $$MOSEKHOME)
ifeq ($(MOSEK_HOME),)
  MOSEK_BIN := $(shell which mosek 2>/dev/null)
  ifneq ($(MOSEK_BIN),)
    #MOSEK_HOME := $(dir $(dir $(MOSEK_BIN)))
    MOSEK_HOME := $(shell dirname $$(dirname $$(realpath $$(which mosek 2>/dev/null))) )
  endif
endif



# Location of include and lib for GUROBI
LPSDP_GUROBI_IL := -I$(GUROBI_HOME)/include/ -L$(GUROBI_HOME)/lib

# Location of incldue and lib for MOSEK
LPSDP_MOSEK_IL :=  -I$(MOSEK_HOME)/h  -L$(MOSEK_HOME)/bin


ifeq ($(UNAME_S),Linux)
    target := gcc
    LPSDP_GUROBI :=  -O3  -std=c++2a  -lgurobi_c++ -lgurobi110 -I/home/lidickyb/lib/ -llapack -lblas -o lpsdp -fopenmp -DGUROBI -g
    LPSDP_MOSEK  :=  -O3   -std=c++2a  -lopenblas  -o lpsdpM -lmosek64 -DMOSEK  -fopenmp -g

    # This is for bernard :-)
    LPSDP_GUROBI_IL_B :=  -I/home/bernard/bin/gurobi/linux64/include -L/home/bernard/bin/gurobi/linux64/lib
    LPSDP_MOSEK_IL_B  :=  -I/home/bernard/mosek/current/tools/platform/linux64x86/h  -L/home/bernard/mosek/current/tools/platform/linux64x86/bin 
endif

ifeq ($(UNAME_S),Darwin)
    CC := g++
    ifneq (, $(shell which g++-mp-10))
      CC := g++-mp-10
    endif
    ifneq (, $(shell which g++-11))
      CC := g++-11
    endif
    ifneq (, $(shell which g++-12))
      CC := g++-12 -arch arm64 
    endif
    ifneq (, $(shell which g++-13))
      CC := g++-13 -arch arm64 
    endif
    ifneq (, $(shell which g++-14))
      CC := g++-14  -arch arm64 
    endif
    ifneq (, $(shell which g++-15))
      CC := g++-15  -arch arm64 
    endif

    LPSDP_GUROBI := -DLP_DOUBLE  -O3  -std=c++20  -lgurobi_c++ -lgurobi120  -llapack -lblas   -DGUROBI
    LPSDP_MOSEK  := -DLP_DOUBLE -O3  -std=c++20  -llapack -lblas  -lmosek64 -DMOSEK
    LPSDP_MOSEK  := -DLP_DOUBLE -g  -std=c++20  -llapack -lblas  -lmosek64 -DMOSEK
    # LPSDP_MOSEK  := -O3  -std=c++20  -llapack -lblas  -lmosek64 -DMOSEK

    LPSDP_MOSEK_IL_B   :=  -I/Users/bernard/mosek/tools/platform/osxaarch64/h/  -L/Users/bernard/mosek/tools/platform/osxaarch64/bin/ -I/Users/lidicky/mosek/tools/platform/osxaarch64/h/ -L/Users/lidicky/mosek/tools/platform/osxaarch64/bin/ 
    LPSDP_GUROBI_IL_B  := -I/Library/gurobi1201/macos_universal2/include/  -L/Library/gurobi1201/macos_universal2/lib/
endif


ifeq ($(findstring alderaan,$(shell hostname)),alderaan)
    $(info Hostname contains 'alderaan')
    LPSDP_MOSEK  :=  -O3    -std=c++2a  -lopenblas  -lmosek64 -DMOSEK  -fopenmp -g
    LPSDP_GUROBI := -O3   -std=c++2a  -lgurobi_c++ -lgurobi120 -I/home/lidickyb/lib/ -lopenblas  -fopenmp -DGUROBI -g

    LPSDP_GUROBI_IL_B := -I/home/lidickyb/gurobi1201/linux64/include/ -L/home/lidickyb/gurobi1201/linux64/lib/
    LPSDP_MOSEK_IL_B := -I/home/lidickyb/mosek/current/tools/platform/linux64x86/h  -L/home/lidickyb/mosek/current/tools/platform/linux64x86/bin 
endif

all: lpsdp


.PHONY: lpsdp
.PHONY: lpsdpM
.PHONY: lpsdpG

lpsdpM:
	g++ lpsdp.cpp  $(LPSDP_MOSEK) $(LPSDP_MOSEK_IL) $(LPSDP_MOSEK_IL_B)  -o lpsdpM
	g++ lpsdp.cpp  -DLP_DOUBLE $(LPSDP_MOSEK) $(LPSDP_MOSEK_IL) $(LPSDP_MOSEK_IL_B)  -o lpsdpMd

lpsdpG:
	g++ lpsdp.cpp $(LPSDP_GUROBI) $(LPSDP_GUROBI_IL) $(LPSDP_GUROBI_IL_B)   -o lpsdpG
	g++ lpsdp.cpp -DLP_DOUBLE $(LPSDP_GUROBI) $(LPSDP_GUROBI_IL) $(LPSDP_GUROBI_IL_B)   -o lpsdpGd


lpsdp: lpsdpM lpsdpG

