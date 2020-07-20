::
:: Batch script for classifying an area defined by a shapefile
::
:: Input is LAS file from e.g. pix4D and a shapefile with polygon of the clipping area
:: Output is one single LAS file where the polygon area has been clipped
::
:: Parameters:
::
:: INFILE: unclassified input LAS file 
:: SHAPEFILE: shapefile with polygons of areas to be clipped
::
:: Processing steps:
:: lasclip creates point cloud only for the clipped area
::
:: Steffen Vogt, 2020-07-17
:: last modified 2020-07-17 13:14:28


echo off

::
:: specify parameters
::

:: Number of cores for parallel processing
set NUM_CORES=4

:: name of shapefile with areas to be smoothed
:: set SHAPEFILE=strohmaier_auggen_clip_grube_2D.shp

:: allows you to run the script from other folders
::set PATH=%PATH%;C:\Programme\LASTools\bin;
set PATH=%PATH%;C:\LASTools\bin;

:: get the input file name for ouptut file name generation
set INFILE=%1


set OUTFILE=%INFILE:~0,-4%_classified_coarse_step_250.las

lasground_new -i %INFILE% ^
              -o %OUTFILE% ^
              -all_returns ^
              -step 2.5 ^
              -coarse ^
              -cpu64 ^
              -cores %NUM_CORES%





:: replace System / Software tags in output file

lasinfo -i %OUTFILE% ^
        -set_system_identifier "svGeo photogrammetry" ^
        -set_generating_software "svGeo las_pipe"