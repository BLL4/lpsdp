# SDP solver using cutting plane method and LP solver
# Written by Bernard Lidicky 2025
# 
#
# This is a simple version of the solver that demonstrates the method
# when running in SageMath.
# It is not optimized for speed or memory.
#
# TODO: Store symmetric matrices as only upper diagonal
# TODO: Store only nonzero matrices
#
#
# 

import sys



field=Integer

def rescale_number(x, constants_rescale, kill_if_fail=True):
    """ Rescaling and testing that rescaling indeed gives an integer"""
    
    if constants_rescale == 1:
        return field(float(x))
    
    x_float = float(x)*constants_rescale
    x_rounded = round(x_float)
    if abs(x_float - x_rounded) > 0.0000001:
        print("Rescaling did not work for x=",x," result was",x_rounded,"which is not precise for",x_float)
        print("Try a different rescaling of the semidefinite program.")
        if kill_if_fail:
            sys.exit()
 
    return field(x_rounded)


################################################################################### UTILITIES
# Reads the whole problem as integer program
# the program has to be integral. This is a hack
# for SDP programs that were solved without scaled objective
# and are expensive to resolve
def read_problem_file(filename,constants_rescale=1,constraint_from=0, constraint_to=10000000):
    f = open(filename, 'r')

    line = f.readline()
    line = line.strip()
    num_constraints = int(line)

    line = f.readline()
    line = line.strip()
    num_blocks = int(line)

    line = f.readline()
    parts = line.split()
    block_sizes = []
    for part in parts:
        block_sizes.append(int(part))

    line = f.readline()
    parts = line.split()

    constants = []
    used_constraints=0

    for i in range(num_constraints):
        if i >= constraint_from and i < constraint_to:
            constants.append(rescale_number(parts[i], constants_rescale))
            used_constraints += 1
    """            
    if constants_rescale == 1:
        for i in xrange(num_constraints):
           if i >= constraint_from and i < constraint_to:
               constants.append(field(parts[i]))
               used_constraints += 1
    else:
        for i in xrange(num_constraints):
           if i >= constraint_from and i < constraint_to:
               constants.append(field(int(float(parts[i])*constants_rescale+0.5)))
               used_constraints += 1
    """

    # blocks that are integer numbers right away
    blocks = []
    for size in block_sizes:
        if size < 0:
            #block = [ matrix(ZZ,1,-size) for x in range(num_constraints+1) ]
            block = [ matrix(ZZ,1,-size) for x in range(used_constraints+1) ]
        else:
            block = [ matrix(ZZ,size,size, sparse=True) for x in range(used_constraints+1) ]
            #block = [ matrix(ZZ,size,size, sparse=True) for x in range(num_constraints+1) ]
            #block = [ matrix(QQ,size,size) for x in range(num_constraints+1) ]
        blocks.append(block)


    t_coef = [0]*num_constraints
    while True:
        line = f.readline()
        if len(line) == 0:
            break
        parts = line.split()
        if len(parts) == 0:
            continue
        constraint = int(parts[0])
        # Read also a bit arround to accommodate for mistakes..
        # Blocks are shifted by one
        #if constraint <= constraint_from or constraint > constraint_to:
        #    continue
        block_num = int(parts[1])
        row = int(parts[2])
        column = int(parts[3])
        value = rescale_number(parts[4], constants_rescale)
        '''
        if constants_rescale == 1:
            value = field(parts[4])
        else:
            value = field(float(parts[4])*constants_rescale)
        '''
        if block_sizes[block_num - 1] < 0:
            blocks[block_num - 1][constraint-constraint_from][0, column - 1] += value
            if (-block_sizes[block_num - 1] == num_constraints+1 or  -block_sizes[block_num - 1] == num_constraints+2) and -block_sizes[block_num - 1] == column:
                t_coef[constraint-constraint_from-1] = abs(value)/constants_rescale
        else:
            blocks[block_num - 1][constraint-constraint_from][row - 1, column - 1] += value
            if row != column:
                blocks[block_num - 1][constraint-constraint_from][column - 1, row - 1] += value

    problem = dict()
    problem['num_constraints'] = used_constraints
    problem['num_blocks'] = num_blocks
    problem['block_sizes'] = block_sizes
    problem['blocks'] = blocks
    problem['constants'] = constants
    problem['constants_rescale'] = constants_rescale
    problem['t_coef'] = t_coef
    f.close()
    return problem


def rescale_vector(v):
    """ Rescale a vector of numbers by the constants_rescale factor"""
    nonzeros = [x for x in v if abs(x) > 0.000001]
    if len(nonzeros) == 0:
        return [0]*len(v)
    min_nonzero = min(nonzeros)
    
    return [x/min_nonzero for x in v ]

def solve_using_LP(problem, it=20, verbose=False):

    num_blocks = problem['num_blocks']
    block_sizes = problem['block_sizes']
    blocks = problem['blocks']
    constants = problem['constants']
    num_constraints = problem['num_constraints']
    constants_rescale = problem['constants_rescale']
    t_coef = problem['t_coef']

    #d = MixedIntegerLinearProgram(maximization=True)
    d = MixedIntegerLinearProgram(maximization=False)
    y = d.new_variable(real=True, nonnegative=True)  # will be used as an array of length constants 

    yrange = range(num_constraints)

    ## TODO change the -c to the objective 
    #print("Objective:",[ -c*y[i]  for i,c in enumerate(constants) ])

    #d.set_objective( sum([ -c*y[i]  for i,c in enumerate(constants) ]) )
    d.set_objective( sum([ c*y[i]  for i,c in enumerate(constants) ]) )

    #print('t_coef=',t_coef)
    d.add_constraint(sum([ t_coef[i]*y[i]  for i in yrange ])  == 1)

    
    # Add linear constraints 
    for blockID,blocksize in enumerate(block_sizes):
        if blocksize < 0 and (-blocksize != num_constraints+1) and  (-blocksize != num_constraints+2):
            for constraintID in range(-blocksize):
                #print("blocksize=",blocksize,"blockID=",blockID,"constraintID=",constraintID,"num_blocks=",num_blocks)
                #print([i for i in yrange])
                #print(blocks[blockID])
                #d.add_constraint(sum([ blocks[blockID][i][constraintID,0]*y[i] for i in yrange if blocks[blockID][i][constraintID,0] != 0 ])  >= 0)
                d.add_constraint(sum([ blocks[blockID][i+1][0,constraintID]*y[i] for i in yrange if blocks[blockID][i+1][0,constraintID] != 0 ])  >= 0)
    

    dconstraints = 1 

    for test_run in range(it):

        print("Iter:",test_run+1,end=" ")
        print("Upper bound is",d.solve()/constants_rescale," with ",dconstraints," constraints")

        yval=[ d.get_values(y[i]) for i in  yrange ]

        if verbose:
            print("  yval=",yval)


        # This should run in parallel
        for blockID in range(num_blocks):
            if block_sizes[blockID] <= 0:
                continue

            A=blocks[blockID][0] # just zero matrix of the right size

            for i,yvali in enumerate(yval):
                A += yvali*blocks[blockID][i+1]

            A = matrix(RDF, A,sparse=False)

            if verbose:
                print("Matrix A"+str(blockID+1),"=")
                print(A)

            evs = A.eigenvectors_right()
            #print("Got eigenvectors",evs)

            # Find smallest eigenvalue
            minID = 0
            minval = evs[0][0]
            for i in range(1, len(evs)):
                if evs[i][0] < minval:
                    minID = i
                    minval = evs[i][0]

            # Smallest eigenvalue
            e = evs[minID]

            if verbose:
                print(" lambda=",e[0]," with eigenvector",e[1][0])

            #for e in evs:

            if e[0] < -0.00000001:
                #print("  Eigenvalue",e[0],"with eigenvector",e[1][0])
                v = e[1][0]

                #
                v = vector(rescale_vector(v))
                if verbose:
                    print("  Rescaled eigenvector",v)

                #print("  v=",v)

                # Test if the new constraint violates the current solution
                c = [ v*blocks[blockID][i+1]*v for i in yrange ]  

                #print("c=",c)
                #print("yval=",yval,"yrange=",yrange)

                #print("presum=",[ c[i]*yval[i] for i in yrange])

                # Test if we have an interesting constraint
                new_contraint = sum([ real_part(c[i])*yval[i] for i in yrange])

                #print("Sum=",new_contraint)

                if new_contraint < 0:
                    #print("  Found new constraint",c)
                    # This is somewhat a critical section of the code.
                    d.add_constraint(sum([  real_part(c[i])*y[i]  for i in yrange ])  >= 0)
                    dconstraints += 1
                    if verbose:
                        for i in yrange:
                            print( str(real_part(c[i]))+"*y_"+str(i+1),end=" ")
                        print(" >= 0")
            
        if verbose:
            print()


def solve_dats_using_LP(datsfile, scale, iterations=40, verbose=False):
    p = read_problem_file(datsfile, scale)
    solve_using_LP(p, iterations, verbose)


if __name__ == "__main__":
    datsfile = ""
    scale=1
    iterations = 40
    n = len(sys.argv)
    if n >= 2:
        datsfile = sys.argv[1]
    if n >= 3:
        #scale = int(sys.argv[2])
        # The below is super dangerous but it accepts arguments "like 4*2"
        scale = float(eval(sys.argv[2], {'__builtins__': None})) # CPU, memory
    if n >= 4:
        iterations = int(sys.argv[3])
    if n != 4:
        print("Usage: sage ",sys.argv[1],"[file.dat-s] [scale] [iterations]")

    print("Loading file",datsfile,"with scale",scale)
    p = read_problem_file(datsfile, scale)
    print("Starting optimization with at most",iterations,"iterations")
    solve_using_LP(p, iterations, False)

