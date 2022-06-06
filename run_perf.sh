#!/bin/bash
#SBATCH -prome
#SBATCH --nodes=1
##SBATCH --ntasks-per-node=28
##SBATCH --threads-per-core=1
#SBATCH -J shm_bcast
#SBATCH --time=8:00:00

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


hostname
lscpu

#HPCX_PATH=/homeb/zam/valentin/workspace/hpcx
#source $HPCX_PATH/hpcx-init.sh
#hpcx_load

#module load hpcx-gcc
source $WDIR/hpcx/hpcx-init.sh
hpcx_load

export exe=$HPCX_UCC_DIR/bin/ucc_perftest

pre="-x LD_PRELOAD=$WDIR/ucc/build_rel/install/lib/libucc.so"

nodes=$SLURM_NNODES
PPN=`echo $SLURM_TASKS_PER_NODE | cut --field=1  --delimiter=\(`
NP=$((nodes * PPN))

dry_run=no
common="-x UCC_TLS=ucp,shm -x UCC_TL_SHM_SET_PERF_PARAMS=n ${pre} "
msg_start=1
msg_end=1024

echo "msgrange $((msg_start * 4)) $((msg_end * 4))"
perftest_args="-c bcast -b $msg_start -e $msg_end -w 1000 -n 5000 "
n_runs=5
sock_size=$(lscpu | grep 'Core(s) per socket' | awk '{print $4}')
sock_num=$(lscpu | grep 'Socket(s)' | awk '{print $2}')
numa_num=$(lscpu | grep 'NUMA node(s)' | awk '{print $3}')
numa_per_sock=$((numa_num/sock_num))
numa_size=$((sock_size/numa_per_sock))

#top_r="2 4 8"
top_r="2"
#base_r="2 4 8 $((sock_size/2)) $((sock_size))"
#base_r="2 4 5 8 10 20" #helios
base_r="2 4 8 16" #thor
#base_r="2 4 8 16 32"

declare -A pnames=([bto]="UCC_TL_SHM_BASE_TREE_ONLY" [layout]="UCC_TL_SHM_SEG_LAYOUT" [base_r]="UCC_TL_SHM_BCAST_BASE_RADIX" [top_r]="UCC_TL_SHM_BCAST_TOP_RADIX" [alg]="UCC_TL_SHM_BCAST_ALG" [gm]="UCC_TL_SHM_GROUP_MODE")
declare -A params

function params_to_args {
    args=""
    for k in ${!params[@]}; do
        args="$args -x ${pnames[$k]}=${params[$k]}"
    done
    echo $args
}

function print_params {
    echo "params = {"
    for k in ${!params[@]}; do
        echo "    $k = ${params[$k]}"
    done
    echo "}"
}


# params_to_args

total_time=0
n_single_runs=0
tmpout=$(mktemp)

function run_single {
    args=$1
    cmd="mpirun -np $NP --mca coll ^hcoll,ucc $common $args $exe ${perftest_args}"
    echo $cmd
    if [ $dry_run != "yes" ]; then
    n_single_runs=$((n_single_runs + 1))
    best=
    for ((r=0; r<n_runs; r++)); do
        start_time=$(date +%s)
        $cmd 2>&1 | tee $tmpout
        end_time=$(date +%s)
        total_time=$((total_time + end_time - start_time))
        lat=$(cat $tmpout | awk '{if (NF == 5) {print $5}}' | tr '\n' ' ')
        lat_a=($lat)
        if [ $r -eq 0 ]; then
            best=($lat)
        else
            for j in ${!best[@]}; do
                if (( $(echo "${lat_a[j]} < ${best[j]}" | bc -l) )) ; then
                    best[$j]=${lat_a[j]}
                fi
            done
        fi
    done
    echo "best: ${best[@]}"
    fi
}

# Run BaseTreeOnly
for layout in socket contig mixed; do
    for br in ${base_r}; do
        for A in "ww" "rr"; do
            params=([bto]=y [layout]=${layout} [base_r]=$br [top_r]=2 [alg]=$A)
            print_params
            run_single "$(params_to_args)"
        done
    done
done

# Run 2trees
for GM in socket numa; do
    for layout in socket contig mixed; do
        for br in ${base_r}; do
	    if [ $GM == "socket" -a $sock_size -lt $br ]; then
		    echo "skipping base_r $br for sock_size $sock_size"
	    fi
            if [ $GM == "numa" -a $numa_size -lt $br ]; then
                    echo "skipping base_r $br for numa_size $numa_size"
            fi

	    for tr in ${top_r}; do
	        if [ $GM == "socket" -a $sock_num -lt $tr ]; then
	    	    echo "skipping top_r $tr for sock_num $sock_num"
	        fi
    	        if [ $GM == "numa" -a $numa_num -lt $tr ]; then
		    echo "skipping top_r $tr for numa_num $numa_num"
	        fi

                for A in "ww" "rr" "wr" "rw"; do
                    params=([bto]=n [layout]=${layout} [base_r]=$br [top_r]=$tr [alg]=$A [gm]=$GM)
                    print_params
                    run_single "$(params_to_args)"
                done
    	    done
        done
    done
done

per_single_run=$(echo "scale=2; ${total_time}/${n_single_runs}" | bc -l)
per_cmd=$(echo "scale=2; ${per_single_run}/${n_runs}" | bc -l)

echo
echo "TIMER: total_elapsed ${total_time}, per_single_run ${per_single_run}, per_cmd ${per_cmd}"
