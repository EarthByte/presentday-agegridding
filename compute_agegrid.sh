#!/bin/bash

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# --------------------------  This script creates agegrids ------------------------------
# --- Agegrids are created by running `isopolate` to create a set of densely ------------
# --- interpolated isochrons, then these are used to create a gridded dataset -----------
# --- This script takes about 20 mins on a laptop.
#
# --- Requirements:
#        - GMT 6.0 (or later) 
#          Highly recommended is GMT 6.2+ (due to fix in runtime for sphinterpolate)
#          In GMT 6.0 and 6.1, this script may take several (5+) hours
#        - Python 3
#        - pygplates in you PYTHONPATH (pygplates is available from: 
#          https://www.gplates.org/download.html)
#        - Python scripts: isopolate.py, run_isopolate.py,
#          [optional] reconstruct_features.py   <-- for generating COB mask only
#
# --- Inputs:
#        - Rotation file (as .rot)
#        - Ridge file (as .gpml)
#        - Isochron file (as .gpml)
#        - IsoCOB file (as .gpml)
#        - [optional] COB terranes file (as .gpml)   <-- for generating COB mask only
#        - [optional] Deforming networks file (as .gpml) <-- for generating COB mask only
#
# --- Outputs:
#        - agegrid without any masking ('agegrid_final_nomask_0.nc')
#        - if COB mask is available: agegrid with mask ('agegrid_final_mask_0.nc')
#        - [optional] COB mask grid ('cobmask_global_0Ma.nc)
#
# Created by R Dietmar Muller, Maria Seton, Nicky Wright, Kara Matthews, Sabin Zahirovic
#
# Copyright (c) 2020 The University of Sydney. All rights reserved.
#
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

# ------------------------------------------
# --- Set general parameters ---------------
age=0				# Age of output grid               
framegrid=d			# Region of output grid - 'd' is shorthand for -180/180/-90/90 (W|E|S|N)
grdspace=0.1d		# Resolution of output grid

generate_cob_mask_grids=no		# Create a masking grid based on non-oceanic regions. Options: yes, no
verbose_mode=no					# Show GMT -V output. Options: yes, no

# ------------------------------------------
# --- Set directories and input files ------
data_dir=AgeGridInput

# ---- Files for creating agegrid
rotation_file=${data_dir}/Global_410-0Ma_Rotations_2019_v3.rot
ridge_file=${data_dir}/Global_EarthByte_GeeK07_Ridges_2019_v3.gpml
# isochron_file=${data_dir}/Global_EarthByte_GeeK07_Isochrons_2019_v3.gpml
isochron_file=${data_dir}/Global_EarthByte_GeeK07_Isochrons_presentday_2019_v3.gpml
isocob_file=${data_dir}/Global_EarthByte_GeeK07_IsoCOB_2019_v3.gpml

# --- Files only for creating COB mask grid (i.e., if generate_cob_mask_grids=yes)
# If generating a COB mask grid, then cob_mask_gpml MUST be set
cob_mask_gpml=${data_dir}/Global_EarthByte_GeeK07_COB_Terranes_2019_v3.gpml

# Deforming networks file - this is completely optional
# def_networks_static=${data_dir}/Global_EarthByte_230-0Ma_GK07_AREPS_Deforming_networks_static.gpml

# --- Location of COB mask
# This can be pre-existing file (in which case you should set generate_cob_mask_grids=no)
# otherwise, this is where your COB mask will be generated.
# Note: if generate_cob_mask_grids=yes, any file here will be overwritten.
maskgrd=cobmask_global_${age}Ma.nc

# ------------------------------------------
# --- Directories for final grids ----------

agegrid_output_dir=.			# base path for agegrid output (if you want it saved on a different harddrive etc)

agedir=${agegrid_output_dir}/Agegrids

mkdir -p ${agedir}/NoMask
grdfile=${agedir}/NoMask/agegrid_final_nomask_${age}Ma.nc

mkdir -p ${agedir}/Mask
finalgrd=${agedir}/Mask/agegrid_final_mask_${age}Ma.nc

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# --- You shouldn't need to touch anything below here

echo "    Reconstructing data for $age Ma"

# Directory for temporary files
dir=${age}.0

# rm -rf $dir		# delete tmp folder

if [ ! -s $dir ]; then
	mkdir $dir
fi

# If verbose mode is specified, print to terminal messages
if [ $verbose_mode == "yes" ] ; then
	verbose='-V'
else
	verbose=
fi

# ---------------------------------------------------------
# --- For COB masking grid

# If the masking grid already exists, quickly compare the resolution and region of the masking
# grid and desired agegrid resolution/region, and print warning if they are not the same. 
# This is not an extensive check, but should hopefully catch major issues.

if [ -s ${maskgrd} ]; then
	# Get the resolution and region for the masking grid
	cob_resolution=`gmt grdinfo ${maskgrd} -Cn -o7`
	cob_region_west=`gmt grdinfo ${maskgrd} -Cn -o0`
	cob_region_east=`gmt grdinfo ${maskgrd} -Cn -o1`
	cob_region_south=`gmt grdinfo ${maskgrd} -Cn -o2`
	cob_region_north=`gmt grdinfo ${maskgrd} -Cn -o3`
	
	cob_region=$cob_region_west/$cob_region_east/$cob_region_south/$cob_region_north
	
	# Re-interpret GMT region shorthand
	if [ "$framegrid" == "g" ] || [ "$framegrid" == "0/360/-90/90" ] ; then
		age_region="0/360/-90/90"
	elif [ "$framegrid" == "d" ] || [ "$framegrid" == "-180/180/-90/90" ] ; then
		age_region="-180/180/-90/90"
	else
		age_region=$framegrid
	fi
	
	if [ "$age_region" == "$cob_region" ] ; then
		echo "    Regions are the same"
	else
		echo "    Warning: check that the mask grid and desired age grid regions are the same!"
		echo "    mask grid:  $cob_region    vs    age grid:  $age_region"
	fi
	
	# Note: this is a very basic check, assumes that cob_resolution is in degrees.
	# In particular, it won't pick up 6m vs 0.1d
	if [ "$grdspace" == "${cob_resolution}d" ] || [ "$grdspace" == "${cob_resolution}" ] ; then
		echo "    Resolutions are the same"
	else
		echo "    Warning: Check that the mask grid and desired age grid resolutions are the same!"
		echo "    mask grid:  ${cob_resolution}d    vs    age grid:  $grdspace"
	fi
fi

# --- Check if the mask grid isn't a file OR if generate_cob_mask_grids has been set to true
if [ ! -f ${maskgrd} ] || [ ${generate_cob_mask_grids} == "yes"  ] ; then
	echo "    Masking grid not found OR masking re-grdding enforced. Making masking grid now for ${age} Ma."
	
	# Need to remove existing COB mask grid in age-gridding folder to avoid inconsistenies if gridding fails
	rm ${maskgrd}
	
	# reconstruct COB features
	python reconstruct_features.py -r ${rotation_file} -m ${cob_mask_gpml} -t ${age} -e xy -- cobs
  	
	# check if the deforming file has been set or if the file is empty/non existent
	if [ -z "${def_networks_static}" ] || [ ! -s ${def_networks_static} ]; then
		echo "    No deforming networks file, creating blank file"
		touch reconstructed_def_network_${age}.0Ma.xy # creates a blank file that hopefully reduces the risk of problems if user does not supply the static deforming network geometries
	else
		echo "    Reconstructing deforming networks"
		python reconstruct_features.py -r ${rotation_file} -m ${def_networks_static} -t ${age} -e xy -- def_network			
	fi

	# combine features
	cat reconstructed_cobs_${age}.0Ma.xy reconstructed_def_network_${age}.0Ma.xy > reconstructed_COB_combined_${age}.0Ma.xy
	
	# create COB mask
	gmt grdmask reconstructed_COB_combined_${age}.0Ma.xy -R${framegrid} -I${grdspace} -N1/NaN/NaN $verbose -G${maskgrd}
	
	# file cleanup
	rm reconstructed_cobs_${age}.0Ma.xy reconstructed_def_network_${age}.0Ma.xy reconstructed_COB_combined_${age}.0Ma.xy
	
fi
	
# ---------------------------------------------------------
# --- Run isopolate
# This step uses python and pygplates to interpolate isochrons
# Creates: 'InterpolatedIsochrons_${age}Ma.xy' and 'InterpolatedIsochrons.gpml'
python run_Isopolate.py $age $rotation_file $ridge_file $isochron_file $isocob_file

# --- isopolate output files
mv InterpolatedIsochrons.gpml $dir            # this gpml is in case you need it for debugging interpolation issues
mv InterpolatedIsochrons_${age}Ma.xy $dir     # xy file with all the spreading parameters. 

# --- new input files 
agefile=${dir}/InterpolatedIsochrons_${age}Ma.xy

# --- convert absolute age to relative age
echo "    Densely interpolating ${agefile}"
# Not strictly needed for present-day
awk -v recon_age=${age} '{ if ($1 == ">") {print $0} else {print $1, $2, $3-recon_age}}' $agefile > ${dir}/tmp0

# --------
# # --- This part of the workflow is not strictly needed, but keeping just in case...
# gmt mapproject ${dir}/tmp0 -Gd -m $verbose > ${dir}/tmp1
# awk 'x !~ $1; {x=$1}' ${dir}/tmp1 > ${dir}/tmp2    # Delete duplicate points that would otherwise crash SAMPLE1D
#
# # Delete points that lie along the northern, southern, and eastern 'cartesian' geographic boundaries to reduce problems with spherical interpolation
# awk '($1 != -180) {print $0}' ${dir}/tmp2 | awk '($2 != -90) {print $0}' | awk '($2 != 90) {print $0}' > ${dir}/tmp2a
#
# # use gmtselect to get file in 2 parts first, since otherwise things don't interpolate very well at the 180/-180 line. This will produce warnings using sample1d, which can be ignored NW 20151003
# # Densify isochrons at required resolution intervals - can be increased.
# gmt gmtselect -R0/180/-90/90  ${dir}/tmp2a ${verbose} -m | gmt sample1d -Af -T3 -I${grdspace} -o0,1,2 ${verbose} > ${dir}/tmp3
# gmt gmtselect -R-180/0/-90/90 ${dir}/tmp2a ${verbose} -m | gmt sample1d -Af -T3 -I${grdspace} -o0,1,2 ${verbose} > ${dir}/tmp4
# cat ${dir}/tmp3 ${dir}/tmp4 > ${dir}/tmp5
#
# # --- SAMPLE1D fails when points are duplicated along the isochron
# if [ -s ${dir}/tmp3 ] && [ -s ${dir}/tmp4 ]; then
# 	echo "    SAMPLE1D successful, continuing agegridding process"
# else
# 	echo "    SAMPLE1D unsuccessful, going to plan B"
# 	gmt mapproject ${dir}/tmp1 -Gd- -m ${verbose} > ${dir}/aa_tmp1
# 	awk '{if ($0 ~/>/) {print $0} else if ( $4 == "0" || $5 > "0" ) {print $1, $2, $3, $4}}' ${dir}/aa_tmp1 > ${dir}/aa_tmp2
# 	awk 'x !~ $0; {x=$0}' ${dir}/aa_tmp2 > ${dir}/aa_tmp3
#
# 	# --- use gmtselect to get file in 2 parts first, since otherwise things don't interpolate very well at the 180/-180 line. This will produce warnings using sample1d, which can be ignored
# 	# Densify isochrons at selected degree intervals
# 	gmt gmtselect -R0/180/-90/90  ${dir}/aa_tmp3 ${verbose} -m | gmt sample1d -Af -T3 -I${grdspace} -o0,1,2 ${verbose} > ${dir}/tmp3
# 	gmt gmtselect -R-180/0/-90/90 ${dir}/aa_tmp3 ${verbose} -m | gmt sample1d -Af -T3 -I${grdspace} -o0,1,2 ${verbose} > ${dir}/tmp4
# 	cat ${dir}/tmp3 ${dir}/tmp4 > ${dir}/tmp5
# fi
# --------

# --- grid xy file
infile=${dir}/tmp0				# output before sample1d etc
# infile=${dir}/tmp5			# output using sample1d etc

gmt blockmedian ${infile} -I${grdspace} -R${framegrid} ${verbose} > ${dir}/tmp-${age}.xyz

echo "    Running sphinterpolate. This may take a while..."
# Use spherical interpolation in GMT 6+ to produce global grid (note that it takes about 20 minutes for a 6-arc-min grid)
# Note: in GMT6.0 and 6.1, this actually takes 8 hours. This is now fixed for GMT6.2+ (fixed in GMT 6.2.0_6830bc9_2020.09.27)
gmt sphinterpolate ${dir}/tmp-${age}.xyz -R${framegrid} -I${grdspace} -Q0 $verbose -G${dir}/tmp.grd?"age"

# Ensure that there are no negative values in the age-grid that are introduced by interpolation
gmt grdclip ${dir}/tmp.grd ${verbose} -Sb0.01/0.01 -G${grdfile}

# Create masked grid
gmt grdmath ${grdfile} ${maskgrd} OR $verbose = ${dir}/${age}.nc

# Needed if you need a CLASSIC netcdf grid (converts netcdf4 grid to netcdf3) - conversion not necessary for GPlates 2.1 or newer
# Commented out by default - if needed, activate the NCCOPY line
cp ${dir}/${age}.nc ${finalgrd}
# nccopy -k 1 ${dir}/${age}.nc ${finalgrd}

# --- file cleanup - so it does not take a ridiculous amount of space!
rm ${dir}/tmp0 ${dir}/tmp1 ${dir}/tmp2 ${dir}/tmp2a ${dir}/tmp3 ${dir}/tmp4 ${dir}/tmp5 ${dir}/tmp-${age}.xyz ${dir}/${age}.nc ${dir}/tmp.grd
rm ${dir}/InterpolatedIsochrons_${age}Ma.xy
rm ${dir}/*.gpml # Comment out if you want to keep isopolate output for debugging


echo "    Finished creating ${age} Ma agegrid:          $(date)"
