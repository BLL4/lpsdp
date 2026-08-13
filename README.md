# lpsdp
Semidefinite programming solver using linear programming.
This is par of paper *Solving Large SDPs from Flag Algebra Problems* written by
[Bernard Lidický](https://lidicky.name) and  [Jan Volec](https://honza.ucw.cz). This implementation was written by [Bernard Lidický](https://lidicky.name).

The data for the actual paper can be found at [https://lidicky.name/pub/lpsdp/](https://lidicky.name/pub/lpsdp/).

We provide three implementations of the solver. There is an early implementation in SageMath, then better implementation in Python and the most efficient implementation in C++. Only the last one was actually used in the paper.

This solver is capable to attempting to solve semidefinite programs coming from flag algebras that are too large to be solver by [CSDP](https://github.com/coin-or/Csdp). 


## Examples

- `mantel_n3_scale_3.dat-s` Formulation of Mantel's theorem using flag algebras on 3 vertices.
The program is scaled by 3 in order to have all entries integers. Optimal solution is -1.5.
This is more of a demo instance.

- `tetrahedron_n6.dat-s` Turán's Tetrahedron problem formualte using flag algebras on 6 vertices.
The program is not scaled. It needs to be scaled by 100 before the solvers can be used. Optimal solution by CSDP is -0.56166722.
This is closer to an actual instance we needed.

- `test.sh` Attempts to run all three solvers on both instances. It also includes a run of CSDP if present in the path. 

## C++ implementation

The most efficient version. This version is under development. 
Requirements
- C++ solver (Linux or MacOS)
- [GUROBI](https://www.gurobi.com) or [MOSEK](https://www.mosek.com) solvers.
Either one will work. Both offer free academic licenses.
- blas/lapack
- openMP


## Python verimplementationsion

The python version is slightly more effective than SageMath version. 
It is the second implementation. 
In order to run it, one needs to 

`pip3 install gurobipy psutil scipy`

*This version is not under active development. It is here as an example.*

## SageMath implementation

The SageMath version was the first implementation. 

*This version is not under active development. It is here as an example.*
