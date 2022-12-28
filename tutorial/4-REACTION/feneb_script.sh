#!/bin/bash
#-------------------------------------------------------------------------------------------------------------
# This is an example script to run a FENEB optimization starting with
# an initial band of 15 images, and running them in parallel.
#
# It is assumed that at least 15 cpu threads are available.
#
# Written by Jonathan A. Semelak
#-------------------------------------------------------------------------------------------------------------
SANDER=sander                                         #Should be replaced by the corresponding path to sander
FENEB=/home/jsemelak/Programs/feneb/feneb             #Should be replaced by the corresponding path to feneb
MDIN=prod.mdin                                        #Sander input
TOPOLOGY=ALAD.prmtop                                  #Topology file
NAME=ALAD                                             #Prefix for all coordinates files.
IMAGES=15                                             #Number of images
STARTSTEP=1                                           #Starting optimization step.
MAXSTEPS=10                                           #Maximum optimization steps to be performed.
DELETENC=1                                            #Delete .nc files after processing ("1" for True)
GREPEVOLUTION=1                                       #Append band and maxgrad evolution ("1" for True)
NAPTIME=10                                            #How long should the script sleep
UNITS=s                                               #In which units (h,s,m)
#-------------------------------------------------------------------------------------------------------------
#NOTES:
#[1] The directory where this script is executed must contain $TOPOLOGY, $MDIN, and feneb.in files, as well
#as a directory called called $STARTSTEP-1, with the coordinates corresponding to
#the previous band ("0", in case $STARTSTEP=1).
#This directory is automatically generated, but if this is the first step, must be manually created
#[2] Before executing the feneb code, this script checks whether the $IMAGES MD runs have finished or not
# If it is not the case, the scriptsleeps a $NAPTIME $m time and checks again
# Usually only a couple of minutes (or even seconds) are necesary
#-------------------------------------------------------------------------------------------------------------

for ((i=STARTSTEP; i<=MAXSTEPS; i++)); # Optimization loop
     do
        mkdir -p $i #Creates a directory for the $i-th optimization step
        cd $i
        #Copy input files and topology
        cp ../$MDIN .
        cp ../feneb.in .
        cp ../$TOPOLOGY  .
        #Copy coordinates from previous optimization step ("0" if this is the first optimization step)
        j=$(($i-1|bc)) #Previous optimization step
        if [ $i == "1" ] #If this is the first optimization step, copy _r_ files to _f_
          then
          for ((k=1; k<=IMAGES; k++));
            do
              cp ../$j/${NAME}_r_${k}.rst7 .
              cp ${NAME}_r_${k}.rst7 ${NAME}_fprev_${k}.rst7
            done
        else #copy _f_ files from previous step and call them _fprev_
          for ((k=1; k<=IMAGES; k++));
            do
              cp ../$j/${NAME}_o_${k}.rst7 ${NAME}_r_${k}.rst7
              cp ../$j/${NAME}_f_${k}.rst7 ${NAME}_fprev_${k}.rst7
          done
        fi
        echo "Running MD"
        for ((k=1; k<IMAGES; k++)); # Start running $IMAGES -1 MD
        do
        $SANDER -O -i prod.mdin \
                   -o prod_${k}.out \
                   -p $TOPOLOGY \
                   -c ${NAME}_fprev_${k}.rst7 \
                   -r ${NAME}_f_${k}.rst7 \
                   -x ${NAME}_f_${k}.nc \
                   -ref ${NAME}_r_${k}.rst7 &
        done
        #Run the last MD, and waits until its finished
        $SANDER -O -i prod.mdin \
                   -o prod_${k}.out \
                   -p $TOPOLOGY \
                   -c ${NAME}_fprev_${k}.rst7 \
                   -r ${NAME}_f_${k}.rst7 \
                   -x ${NAME}_f_${k}.nc \
                   -ref ${NAME}_r_${k}.rst7
	      #Check if all Images have finished
	      count=0
        while [ $count -lt $IMAGES ];
          do
            count=0
            for ((k=1; k<=IMAGES; k++));
              do
                if  grep -s -q -F "wallclock()" "prod_${k}.out";
                then
                count=$((count+1))
                else
                echo "image number " ${k} "has not finished"
                fi
              done
            if [ $count == $IMAGES ]
            then
            echo "all Images have finished"
            else
            echo "taking a" $NAPTIME $UNITS " long nap..."
	          echo "..."
            fi
        done
        #Run feneb
        echo "Running feneb optimization"
        $FENEB
        if [ $DELETENC == "1" ] #Delete .nc files
          then
          rm *.nc
        fi
        for ((k=1; k<=IMAGES; k++)); #Copy files for next movement
          do
            cp ${NAME}_o_${k}.rst7 _r_${k}.rst7
          done

        if [ $GREPEVOLUTION == "1" ] #Copy optimization information to .dat files
          then
          GRADPERP=$(grep "Band max force:" feneb.out|awk '{print $4}')
          cat profile.dat >> ../bandevolution.dat
          echo " " >> ../bandevolution.dat
          echo $i $GRADPERP >> ../maxgradevolution.dat
        fi
        echo "Step: "$i " finished"
        cd ..
done
