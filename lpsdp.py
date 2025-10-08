#
#
#
# Todo: Add only most negative * 1/2. This should avoid duplicit inequalities.
# count non-zeros in y
#
# When constrained dropped, remember if it how violated later and how much swas it. 
#
# TODO: Keep only the vector from a constraint, not the whole d/c vector.
#
# Creating a virtual environment for python
#
#  python3.12 -m venv ~/venv 
# source ~/venv/bin/activate
# python3 -m pip install numpy scipy gurobipy psutil

#
# Features to save memory
#  - Store symmetric matrices as only upper diagonal
#  - Stored as int32 and retype to float later whenever in use
#
# Try clustering the input file by blocks. Then the blocks could all be processed
# separately (either in parallel or serial). Either way it should decrease the memory.
# The best sort is perhaps first by blocks and then by the graph ID
# 
#
# Requires numpy, scipy and gurobipy 
#
# One needs to do
# pip3 install numpy scipy gurobipy
#
# This should work:
# python3 -m pip install numpy scipy gurobipy psutil
#
# from sdpsolver import *
#
# 
''' Description of dat-s files
// In our UPPER BOUND application
//
//      min    t   
//      s.t.  D_i + [A.X]_i <= t    
//
// We add a slack variable s_i to make the <= to = and move D_i (density - constant to the other side)
// and change to maximization problem in dat-s file
//
//      max   -t
//      s.t.  [A.X]_i + s_i - t = -D_i
//
Dual: 

minimize  -D_i y_i
st.    sum y_i A_i posdef 
     y_i  == 1


// Now LOWER BOUND application
//
//      max    t
//      s.t.  D_i - [A.X]_i  >= t
//
// We add a slack variable s_i to make the >= to = and move D_i (density - constant to the other side)
// and change to maximization:
//
//      max   t
//      s.t.  [A.X]_i + s_i + t = D_i

Dual  
minimize  D_i y_i
st.    sum y_i A_i posdef 
     y_i  == 1


'''

import sys
import gurobipy as gp
from gurobipy import GRB
import numpy as np
import time
import subprocess
import psutil
import os
import pickle
import gc
import argparse

import concurrent.futures


# lil_matrix and csr_matrix are sparse matrices
# where lil is better for loading and csr for calculation
from scipy.sparse import lil_matrix, csr_matrix

from scipy.sparse.linalg import eigsh  # For symmetric matrices



def rescale_number(x, constants_rescale, kill_if_fail=True):
    """ Rescales and ensures the number is an integer."""

    x_float = float(x) * constants_rescale
    x_rounded = round(x_float)

    if abs(x_float - x_rounded) > 1e-5:
        print(f"Rescaling did not work for x={x}, result was {x_rounded}, which is not precise for {x_float}")
        print("Try a different rescaling of the semidefinite program.")
        if kill_if_fail:
            sys.exit()

    return int(x_rounded)


def read_problem_file(filename, constants_rescale=1):
    """ Reads an integer linear program problem from a file and converts it into NumPy-based data structures. """
    
    filename_pkl = filename + ".pkl"
    if os.path.exists(filename_pkl):
        with open(filename_pkl,"rb") as f:  # Python 3: open(..., 'rb')
            start_time = time.time()
            print("Loading from file",filename_pkl)
            result=pickle.load(f)
            print(f"Loading done, took {(time.time()-start_time):.2f} seconds")
            return result

    total_lines=int(subprocess.check_output("wc -l "+filename,shell=True).split()[0])

    start_time = time.time()

    # Get the process ID (PID) of the current Python script
    pid = os.getpid()

    # Get the process using psutil
    process = psutil.Process(pid)

    with open(filename, 'r', buffering=1024*1024) as f:
        num_constraints = int(f.readline().strip())
        num_blocks = int(f.readline().strip())

        # Read block sizes
        block_sizes = list(map(int, f.readline().strip().split()))

        # Read constants
        constants = []
        parts = f.readline().strip().split()
        used_constraints = 0

        for i in range(num_constraints):
            constants.append(rescale_number(parts[i], constants_rescale))
            used_constraints += 1

        # If we allocate all the blocks in advance, it may take too long to even allocate the data
        # so we allcoate the blocks only when we really need them.
        #

        blocks = []
        for size in block_sizes:
            block = [None for _ in range(used_constraints + 1)]
            blocks.append(block)

        if num_constraints > 10000:
            print("Reading input started")

        # Read matrix elements
        t_coef = [0]*num_constraints

        last_constraint_id = 0
        last_blocks_touched=set()

        lineid = 4 
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue

            lineid += 1
            if lineid%1_000_000 == 0:
                collected = gc.collect()
                time_taken = time.time() - start_time
                donepercentage = 100*lineid/total_lines
                time_to_finish = time_taken/donepercentage * (100 - donepercentage)
                # Get memory usage in bytes
                memory_info = process.memory_info().rss  # Resident Set Size (RSS) - memory currently in use
                # Convert bytes to megabytes
                memory_usage_gb = memory_info / (1024 * 1024 * 1024)
                print("  Reading line",lineid,'out of',total_lines,' Done', f"{donepercentage:.2f}% Time taken {time_taken:.2f}s  Time to finish  {time_to_finish:.2f}s Memory usage: {memory_usage_gb:.2f} GB, GC: {collected}")

            constraint = int(parts[0])
            block_num = int(parts[1]) - 1  # Adjust for 0-based indexing
            row = int(parts[2]) - 1
            column = int(parts[3]) - 1
            size = block_sizes[block_num]

            # New: We load off diagonal as 2x so we can caluclate the whole thing as B + B^T
            if size > 0 and row != column:
                value = rescale_number(parts[4], 2*constants_rescale)
            else:
                value = rescale_number(parts[4], constants_rescale)

            '''
            if constraint != last_constraint_id:
                rebuilt = 0
                for blockid in last_blocks_touched:
                    if blocks[blockid][last_constraint_id] != None:
                        blocks[blockid][last_constraint_id] = csr_matrix(blocks[blockid][last_constraint_id])
                        rebuilt += 1
                last_blocks_touched=set()
                last_constraint_id = constraint
            '''


            # We do not need the block with the slack variables and objective
            # function so we skip those blocks
            #
            if size < 0:
                if -size != used_constraints+1 and -size != used_constraints+2:
                    if blocks[block_num][constraint] == None:
                        blocks[block_num][constraint] = lil_matrix((1, -size), dtype=np.int32)

                    blocks[block_num][constraint][0,column] = value

                else:
                    if constraint == 0:
                        continue
                    if used_constraints == column:
                        t_coef[constraint-1] = abs(value)/constants_rescale

            else:
                if size == 0:
                    print("block_num=",block_num,"has size=",size)
                if blocks[block_num][constraint] == None:
                    blocks[block_num][constraint] = lil_matrix((size, size), dtype=np.int32)
                blocks[block_num][constraint][row, column] = value



    if num_constraints > 10000:
        print("  Rebuilding matrices")
    blocks_csr = [  [  csr_matrix(M) if M is not None else None for M in block  ]  for block in blocks]
    if num_constraints > 10000:
        print("  Problem loaded")

    print("Collected ",gc.collect(),"garbage")


    problem={
            "num_constraints": used_constraints,
            "num_blocks": num_blocks,
            "block_sizes": block_sizes,
            "blocks": blocks_csr,
            "constants": constants,
            "constants_rescale": constants_rescale,
            't_coef': t_coef,
        }

    with open(filename_pkl, 'wb') as f:  # Python 3: open(..., 'rb')
        print("Saving pkl for future in",filename_pkl)
        pickle.dump(problem, f)

    # Return problem as a dictionary
    return problem


def process_block(block, blocksize, blockID, yval, yrange, verbose):


    if blocksize > 0:
        return  process_SDP_block(block, blocksize, blockID, yval, yrange, verbose)
    
    #if block_sizes[blockID] <= 0:
    return []


def process_SDP_block(block, blocksize, blockID, yval, yrange, verbose):
    """Process each block, possibly in parallel, checking constraints and returning new ones.
    Call as process_SDP_block(blocks[blockID], block_size[blockID], blockID, yval, yrange)
    """

    # Get the process ID (PID) of the current Python script
    pid = os.getpid()
    # Get the process using psutil
    process = psutil.Process(pid)    


    A = None
    AisEmpty = True

    start_time_A=time.time()

    # Get memory usage in bytes
    memory_info = process.memory_info().rss  # Resident Set Size (RSS) - memory currently in use
    # Convert bytes to megabytes
    memory_usage_gb = memory_info / (1024 * 1024 * 1024)

    for i, yvali in enumerate(yval):
        # Dont bother with essentially zeros. Could do some speedup
        if abs(yvali) < 0.00000001:
            continue
        if AisEmpty:
            if block[i + 1] != None:
                A = yvali * block[i + 1].astype(np.float64)
                AisEmpty = False
                if verbose:
                    print(f"  Block {blockID} of size {blocksize} started processing, memory {memory_usage_gb:.2f}GB, pid={pid}") 

        else: 
            if block[i + 1] != None:
                A += yvali * block[i + 1].astype(np.float64)


    if AisEmpty:
        return []
    

    A = A + A.T 

    time_A=time.time()-start_time_A

    #print("A built for",blockID)

    start_time_eig=time.time()

    evs = np.linalg.eigh(A.toarray())  # Eigen decomposition - our matrices are symmetric

    min_index = np.argmin(evs[0])
    min_eigenvalue = evs[0][min_index]
    evec = evs[1].T[min_index]   # Here the transpose must be first, otherwise does not work.
    
    time_eig=time.time()-start_time_eig

    new_constraints = []

    start_time_c=time.time()

    negative_vectors=[]

    negative_vectors = [evec]
    negative_eigenvalues = [min_eigenvalue]

    #print("Min_index=",min_index,"evs[0]",evs[0][min_index],'evs[1]',evs[1][min_index])
    #print("negative_eigenvalues=",negative_eigenvalues)
    #print("negative_vectors=",negative_vectors)

    #negative_vectors = [ evec for ev, evec in zip(evs[0], evs[1].T) if ev <=  min_eigenvalue ]
    #negative_eigenvalues = [ ev for ev in evs[0] if ev <=  min_eigenvalue ]


    #print("negative_eigenvalues=",negative_eigenvalues)
    #print("negative_vectors=",negative_vectors)


    if min_eigenvalue < 0:

        ds = [ {} for i in range(len(negative_vectors))  ]

        get_ds_from_block(block, yrange, ds, negative_vectors)

        for d, ev, evc in zip(ds, negative_eigenvalues, negative_vectors):
            new_constraint_val = sum(d[i] * yval[i] for i in d.keys())
            #if new_constraint_val < 0:
            if True or new_constraint_val < 0.000000001:
                constrain={}
                constrain['blockID'] = blockID
                constrain['v'] = evc
                constrain['d'] = d
                new_constraints.append(constrain)
            else:
                if verbose and False:
                    print("    Numerical error, eigenvalue of v(yA)v=",ev," but  y*(vAv)=",new_constraint_val)
                #print("XXXX",new_constraint_val)

    else:
        if verbose:
            print("  Block is positive definite. Smalles eigenvalue is ",min_eigenvalue)

    time_c=time.time()-start_time_c

    if verbose:
        # Get memory usage in bytes
        memory_info = process.memory_info().rss  # Resident Set Size (RSS) - memory currently in use
        # Convert bytes to megabytes
        memory_usage_gb = memory_info / (1024 * 1024 * 1024)        
        print(f"  Block {blockID} of size  processed in {time_A:.2f}s (A), {time_eig:.2f}s (eig), {time_c:.2f}s (c), {len(new_constraints)} new constraints found. Memory {memory_usage_gb:.2f}GB")

    return new_constraints


def get_ds_from_block(block, yrange, ds, constraint_vectors):
        
        for k in range(yrange):
            if block[k + 1] != None:

                B = block[k + 1]
    
                for d, v in zip(ds, constraint_vectors): 

                    # The calculation below is doing 
                    value=2*np.real(v @ ( B @ v) )

                    '''
                    value = 0
                    dim = B.shape[0]
                    for i in range(dim):
                        for j, Bij in zip(B.indices[B.indptr[i]:B.indptr[i+1]],B.data[B.indptr[i]:B.indptr[i+1]]):
                            value += v[i]*v[j]*Bij
                    value *= 2
                    '''

                    if abs(value) > 0.000000000001:
                        d[k] = value


def add_constraints_from_ckeckpoint(model, load_checkpoint, filename_checkpoint_pkl, num_constraints, blocks, y, drop_threshold, verbose):

    dconstraints = 1
    constraints_in_model = {}

    load_checkpoint_filename = None

    if load_checkpoint == True:
        file1 = filename_checkpoint_pkl[0]
        file2 = filename_checkpoint_pkl[1]
        load_checkpoint_filename = file1

        if os.path.exists(file1) and os.path.exists(file2):
            if os.path.getmtime(file1) < os.path.getmtime(file2):
                load_checkpoint_filename = file2
                #print(f"{file2} is newer than {file1}")
        elif os.path.exists(file2):
            #print(f"Only {file2} exists.")
            load_checkpoint_filename = file2

    if isinstance(load_checkpoint, str):
        load_checkpoint_filename = load_checkpoint

    if load_checkpoint_filename != None:
        if os.path.exists(load_checkpoint_filename):
            with open(load_checkpoint_filename, 'rb') as f: 
                try:
                    start_time = time.time()
                    constraints_in_model = pickle.load(f)
                    if verbose:
                        time_taken = time.time() - start_time
                        print(f"Unipckling file {load_checkpoint_filename} took {time_taken:.2f}s")                    
                except EOFError:
                    print("Checkpoint file",load_checkpoint_filename,"is damaged")
                    constraints_in_model = {}
        else:
            print("Checkpoint file",load_checkpoint_filename,"does not exist")
    else:
        return constraints_in_model, dconstraints


    if verbose:
        print("Loaded",len(constraints_in_model),"constraints from checkpoint")

    start_time = time.time()
    #
    added_constraints = 0
    dropped_constraints = 0
    #
    v_contraints = {}
    for name, constraint in constraints_in_model.items():


        if 'slack' in constraint:
            if drop_threshold != None:
                if constraint['slack'] > drop_threshold:
                    dropped_constraints += 1
                    continue

        if 'c' in constraint:
            model.addConstr(gp.quicksum(np.real(constraint['c'][i]) * y[i] for i in range(num_constraints) if abs(constraint['c'][i]) > 0.00000000001 ) >= 0, name=name)
            del constraint['c']
            added_constraints += 1
        elif 'd' in constraint:
            model.addConstr(gp.quicksum(np.real(coef) * y[i] for i,coef in constraint['d'].items()) >= 0, name=name)
            del constraint['d']
            added_constraints += 1
        elif 'v' in constraint:
            if constraint['blockID'] in v_contraints:
                v_contraints[constraint['blockID']].append(constraint['v'])
            else:
                v_contraints[constraint['blockID']] = [constraint['v']]

        ID = int(name[2:])
        if ID >= dconstraints:
            dconstraints = ID + 1

    for blockID in v_contraints:
        ds = [ {} for i in range(len(v_contraints[blockID])) ]
        get_ds_from_block(blocks[blockID], num_constraints, ds, v_contraints[blockID])
        for d in ds:
            model.addConstr(gp.quicksum(np.real(coef) * y[i] for i,coef in d.items()) >= 0, name=name)
            added_constraints += 1

    if verbose:
        time_taken = time.time() - start_time
        print(f"Constraints added in {time_taken:.2f}s")
    if dropped_constraints > 0:
        print("Dropped ",dropped_constraints,"constraints since their slack was more than",drop_threshold)


    return constraints_in_model, dconstraints
    


def solve_using_LP(filename, problem, it=200, load_checkpoint=True, verbose=False, parallel=False, max_workers=None, gurobi_threads=0, gurobi_output=False, drop_threshold=None):
    """Solves LP using Gurobi and parallelized block processing.
        checkpoint can be either True or a filename to load the checkpoint from.
    """

    num_blocks = problem["num_blocks"]
    block_sizes = problem["block_sizes"]
    blocks = problem["blocks"]
    constants = problem["constants"]
    num_constraints = problem["num_constraints"]
    constants_rescale = problem["constants_rescale"]
    t_coef = problem["t_coef"]

    filename_checkpoint_pkl = [ filename + ".checkpointA.pkl", filename + ".checkpointB.pkl"]


    # Get the process ID (PID) of the current Python script
    pid = os.getpid()

    # Get the process using psutil
    process = psutil.Process(pid)

    # Initialize Gurobi model
    model = gp.Model("LP_Solver")
    if gurobi_output == False:
        model.setParam("OutputFlag", 0)  # Suppress output
    model.setParam("Threads", gurobi_threads)  # Number of threads, 0 means use all available

    # Define variables
    y = model.addVars(num_constraints, lb=0, name="y")

    # Objective function: Maximize -sum(constants[i] * y[i])
    model.setObjective(gp.quicksum(constants[i] * y[i] for i in range(num_constraints)), GRB.MINIMIZE)
    

    # Initial constraint: sum(y[i]) == 1
    model.addConstr(gp.quicksum(t_coef[i]*y[i] for i in range(num_constraints)) == 1,name="Sum=1")


    model_constraint=1
    # Add linear constraints 
    for blockID,blocksize in enumerate(block_sizes):
        if blocksize < 0 and (-blocksize != num_constraints+1) and  (-blocksize != num_constraints+2):
            for constraintID in range(-blocksize):
                model.addConstr(gp.quicksum([ blocks[blockID][i+1][0,constraintID]*y[i] for i in range(num_constraints) if blocks[blockID][i+1] != None ])  >= 0, name="MC"+str(model_constraint))
                model_constraint += 1



    constraints_in_model, dconstraints = add_constraints_from_ckeckpoint(model, load_checkpoint, filename_checkpoint_pkl, num_constraints, blocks, y, drop_threshold, verbose)


    start_time = time.time()
    previous_time = start_time
    elapsed_time_lp_start = start_time
    elapsed_time_new_constraints = 0


    for test_run in range(it):
        if verbose:
            print(f"Iter: {test_run + 1}")
        else:
            print(f"Iter: {test_run + 1}", end=" ")

        # Solve LP
        model.optimize()
        upper_bound = model.objVal / constants_rescale

        # Retrieve variable values
        yval = [y[i].X for i in range(num_constraints)]

        y_zeros    = sum([ 1 for i in yval if i == 0 ])
        y_nonzeros = num_constraints - y_zeros

        total_costrs= len(model.getConstrs())
        binding = [c for c in model.getConstrs() if abs(c.Slack) < 1e-5]        

        # Copy slacks
        for c in model.getConstrs():
            ConstrName = c.getAttr("ConstrName")
            if ConstrName in constraints_in_model:
                constraints_in_model[ConstrName]['slack'] = c.Slack
        

        if drop_threshold != None:
            constraints_to_remove = [c for c in model.getConstrs() if abs(c.Slack) > drop_threshold]
            for c in constraints_to_remove:
                ConstrName = c.getAttr("ConstrName")
                if ConstrName in constraints_in_model:
                    del constraints_in_model[ConstrName]
                    model.remove(c)  # We don't want to remove the initial constraints even if useless
                #print("Useless:",c.getAttr("ConstrName"))
        

        # Save the current constraints
        with open(filename_checkpoint_pkl[test_run%2], 'wb') as f: 
            pickle.dump(constraints_in_model, f)

        #model.remove(constraints_to_remove)
        model.update()
        gc.collect()

        elapsed_time_lp = time.time() - elapsed_time_lp_start

        elapsed_time = time.time() - start_time
        elapsed_iter_time = time.time() - previous_time
        # Get memory usage in bytes
        memory_info = process.memory_info().rss  # Resident Set Size (RSS) - memory currently in use
        # Convert bytes to megabytes
        memory_usage_gb = memory_info / (1024 * 1024 * 1024)

        print(f"Upper bound is {upper_bound} with {dconstraints} constraints, {total_costrs} in model {len(binding)} tight; Constraints {elapsed_time_new_constraints:.2f}s, LP {elapsed_time_lp:.2f}s, total {elapsed_time:.2f}s, mem {memory_usage_gb:.2f}GB, y {y_zeros} zeros and {y_nonzeros} nonzeros")
        previous_time = time.time()


        elapsed_time_new_constraints_start = time.time() 


        if verbose:
            print("  Getting new constraints")

        # Parallel execution for block constraints
        new_constraints = []

        # Non-parallel execution for debugging
        
        if parallel == False:
            for blockID in range(num_blocks):
                if block_sizes[blockID] > 0:
                    result = process_block(blocks[blockID], block_sizes[blockID], blockID, yval, num_constraints, verbose)
                    new_constraints.extend(result)
                    #if len(result) > 0:
                    #    print("Got",len(result),"constraints from block",blockID)
        

        ## Note tht the blocks[blockID] are actually copied as memory so it is not super
        # efficient but there seems to be some bug in python when using shared memory,
        # see https://github.com/python/cpython/issues/82300 It may be fixed in Python 3.13
        # so we will try maybe later.
        else:
            with concurrent.futures.ProcessPoolExecutor(max_workers=max_workers) as executor:
                futures = {executor.submit(process_block, blocks[blockID], block_sizes[blockID], blockID, yval, num_constraints, verbose): blockID
                        for blockID in range(num_blocks) if block_sizes[blockID] > 0}

                for future in concurrent.futures.as_completed(futures):
                    #print("Future=",future)
                    try:
                        result = future.result()
                        #print("Result=",result)
                        if result:
                            new_constraints.extend(result)
                    except Exception as e:
                        print(f"Error in worker process: {e}")
                    
        if verbose:
            print(f"  Adding {len(new_constraints)} new constraints to the model")

        if len(new_constraints) == 0:
            print("No new constraints found, done")
            break

        elapsed_time_new_constraints = time.time() - elapsed_time_new_constraints_start

        elapsed_time_lp_start = time.time()
        # Add new constraints sequentially
        for constraint in new_constraints:
            name = "GC"+str(dconstraints)
            constraints_in_model[name] = constraint
            constraint['slack'] = 0  # The constraint is probably violated, so slack is 0
            if 'c' in constraint:
                model.addConstr(gp.quicksum(np.real(constraint['c'][i]) * y[i] for i in range(num_constraints) if abs(constraint['c'][i]) > 0.0000000001) >= 0, name=name)
                del constraint['c']
            if 'd' in constraint:
                model.addConstr(gp.quicksum(np.real(coef) * y[i] for i,coef in constraint['d'].items()) >= 0, name=name)
                del constraint['d']

            dconstraints += 1

    return model



if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Solve a dat-s semidefinite program using Gurobi.')
    parser.add_argument('filename', type=str, help='The dat-s file to solve.')
    parser.add_argument('-s', '--scale', type=float, default=1, help='The scaling factor for the problem.')
    parser.add_argument('-i', '--iterations', type=int, default=200, help='The maximum number of iterations to run.')
    parser.add_argument('-v', '--verbose', action='store_true', help='Print more information.')
    parser.add_argument('-c', '--checkpoint', type=str, default="", help='Load a checkpoint file.')
    parser.add_argument('-dc', '--disable-checkpoint', action='store_true', help='Do not load checkpoint.')
    parser.add_argument('-p', '--parallel', action='store_true', help='Tries to compute eigenvectors and new constraints in parallel.')
    parser.add_argument('-w', '--max-workers', type=int, default=None, help='Maximum number of parallel workers.')
    parser.add_argument('-dt', '--drop-threshold', type=float, default=None, help='Maximum slack allowed for constraints to be kept in LP. Default means all constraints are kept.')
    parser.add_argument('-gt', '--gurobi-threads', type=int, default=0, help='Number of threads for Gurobi to use.')    
    parser.add_argument('-go', '--gurobi-output', action='store_true', help='Print output from gurobi.')
    args = parser.parse_args()

    if args.checkpoint == "":
        args.checkpoint = True

    if args.disable_checkpoint:
        args.checkpoint = False

    print("Loading file",args.filename,"with scale",args.scale)
    p = read_problem_file(args.filename, args.scale)
    print("Starting optimization with at most",args.iterations,"iterations")
    solve_using_LP(args.filename, p, args.iterations, args.checkpoint, args.verbose, args.parallel, args.max_workers, args.gurobi_threads, args.gurobi_output, args.drop_threshold)
