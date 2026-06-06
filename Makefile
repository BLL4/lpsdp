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
    GUROBI_VER = $(shell basename $(GUROBI_HOME) | sed 's/gurobi//' | sed 's/\(.\)\(.\)\(.\)/\1\2/')
    ifeq ($(GUROBI_VER),)
       GUROBI_VER = 130
       $(warning Could not auto-detect Gurobi version, using default: $(GUROBI_VER))
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
    LPSDP_GUROBI := -DGUROBI -O3  -std=c++2a  -lgurobi_c++ -lgurobi$(GUROBI_VER) -llapack -lblas -fopenmp -g
    LPSDP_MOSEK  := -DMOSEK  -O3  -std=c++2a  -lopenblas  -lmosek64  -fopenmp -g
endif

ifeq ($(UNAME_S),Darwin)
    CC := g++
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

    LPSDP_GUROBI := -DLP_DOUBLE -O3  -std=c++20  -lgurobi_c++ -lgurobi120  -llapack -lblas   -DGUROBI
    LPSDP_MOSEK  := -DLP_DOUBLE -O3  -std=c++20  -llapack -lblas  -lmosek64 -DMOSEK

endif


all: lpsdp


.PHONY: lpsdp
.PHONY: lpsdpM
.PHONY: lpsdpG

lpsdpM:
	g++ lpsdp.cpp  $(LPSDP_MOSEK) $(LPSDP_MOSEK_IL)  -o lpsdpM
	g++ lpsdp.cpp  -DLP_DOUBLE $(LPSDP_MOSEK) $(LPSDP_MOSEK_IL)  -o lpsdpMd

lpsdpG:
	g++ lpsdp.cpp $(LPSDP_GUROBI) $(LPSDP_GUROBI_IL)   -o lpsdpG
	g++ lpsdp.cpp -DLP_DOUBLE $(LPSDP_GUROBI) $(LPSDP_GUROBI_IL)  -o lpsdpGd


lpsdp: lpsdpM lpsdpG

