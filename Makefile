UNAME_S := $(shell uname -s)

CXX := "g++"


ifndef LIB_BLASLAPACK

HAVE_ACCELERATE := $(shell \
	printf 'int main(){return 0;}\n' | \
	$(CXX) -x c++ -o /tmp/blas_test_$$$$ - \
		-framework Accelerate \
		>/dev/null 2>&1 && echo yes)

ifeq ($(HAVE_ACCELERATE),yes)

LIB_BLASLAPACK := -framework Accelerate
$(info Using Accelerate)

else

HAVE_OPENBLAS := $(shell \
	printf 'int main(){return 0;}\n' | \
	$(CXX) -x c++ -o /tmp/blas_test_$$$$ - \
		-lopenblas \
		>/dev/null 2>&1 && echo yes)

ifeq ($(HAVE_OPENBLAS),yes)

LIB_BLASLAPACK := -lopenblas
$(info Using OpenBLAS)

else

HAVE_LAPACK := $(shell \
	printf 'int main(){return 0;}\n' | \
	$(CXX) -x c++ -o /tmp/blas_test_$$$$ - \
		-llapack -lblas \
		>/dev/null 2>&1 && echo yes)

ifeq ($(HAVE_LAPACK),yes)

LIB_BLASLAPACK := -llapack -lblas
$(info Using LAPACK + BLAS)

else

$(error Could not find Accelerate, OpenBLAS, or LAPACK/BLAS)

endif
endif
endif
endif

#LIB_BLASLAPACK =  -llapack -lblas
#LIB_BLASLAPACK =  -lopenblas

$(warning lapack and blas is $(LIB_BLASLAPACK)  )

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

GUROBI_VER = $(shell echo $(GUROBI_HOME) | sed 'sX.*gurobi[/]*XX' | sed 's/\.//g' | sed 's/\(.\)\(.\)\(.\).*/\1\2\3/')
ifeq ($(GUROBI_VER),)
   GUROBI_VER = 130
   $(warning Could not auto-detect Gurobi version, using default: $(GUROBI_VER))
endif
$(warning Gurobi home: $(GUROBI_HOME))
$(warning Gurobi version: $(GUROBI_VER))


MOSEK_HOME ?= $(shell echo $$MOSEKHOME)
ifeq ($(MOSEK_HOME),)
  MOSEK_BIN := $(shell which mosek 2>/dev/null)
  ifneq ($(MOSEK_BIN),)
    #MOSEK_HOME := $(dir $(dir $(MOSEK_BIN)))
    MOSEK_HOME := $(shell dirname $$(dirname $$(realpath $$(which mosek 2>/dev/null))) )
  endif
endif
$(warning Mosek home: $(MOSEK_HOME))


# Location of include and lib for GUROBI
LPSDP_GUROBI_IL := -I$(GUROBI_HOME)/include/ -L$(GUROBI_HOME)/lib

# Location of incldue and lib for MOSEK
LPSDP_MOSEK_IL :=  -I$(MOSEK_HOME)/h  -L$(MOSEK_HOME)/bin

ifeq ($(UNAME_S),Linux)
    target := gcc
    LPSDP_GUROBI := -DGUROBI -O3  -std=c++2a  -lgurobi_c++ -lgurobi$(GUROBI_VER) -fopenmp -g
    LPSDP_MOSEK  := -DMOSEK  -O3  -std=c++2a  -lmosek64  -fopenmp -g
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

    LPSDP_GUROBI := -DGUROBI -O3  -std=c++20  -lgurobi_c++ -lgurobi$(GUROBI_VER) 
    LPSDP_MOSEK  := -DMOSEK  -O3  -std=c++20  -lmosek64 

endif


all: lpsdp

lpsdpM:
	$(CXX) lpsdp.cpp  $(LPSDP_MOSEK) $(LPSDP_MOSEK_IL) $(LIB_BLASLAPACK)  -o lpsdpM
	$(CXX) lpsdp.cpp  -DLP_DOUBLE $(LPSDP_MOSEK) $(LPSDP_MOSEK_IL) $(LIB_BLASLAPACK)  -o lpsdpMd

lpsdpG:
	$(CXX) lpsdp.cpp $(LPSDP_GUROBI) $(LPSDP_GUROBI_IL) $(LIB_BLASLAPACK)  -o lpsdpG
	$(CXX) lpsdp.cpp -DLP_DOUBLE $(LPSDP_GUROBI) $(LPSDP_GUROBI_IL) $(LIB_BLASLAPACK) -o lpsdpGd


lpsdp: lpsdpM lpsdpG
m: lpsdpM
mosek: lpsdpM
g: lpsdpG
gurobi: lpsdpG


.PHONY: lpsdp
.PHONY: lpsdpM
.PHONY: lpsdpG
.PHONY: m
.PHONY: g
.PHONY: mosek
.PHONY: gurobi
