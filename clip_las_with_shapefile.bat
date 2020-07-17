::
:: Batch script for clipping an area defined by a shapefile
::
:: Input is LAS file from e.g. pix4D and a shapefile with polygon of the clipping area
:: Output is one single LAS file where the polygon area has been clipped
::
:: Parameters:
::
:: 
:: SHAPEFILE: shapefile with polygons of areas to be clipped
::
:: Processing steps:
:: lasclip creates point cloud only for the clipped area
::
:: Steffen Vogt, 2020-07-03

echo off

::
:: specify parameters
::

:: name of shapefile with areas to be clipped
:: set SHAPEFILE=strohmaier_auggen_clip_grube_2D.shp

:: get the input file name for ouptut file name generation
set INFILE=%1

:: get the input file name for ouptut file name generation
set SHAPEFILE=%2

set OUTFILE=%INFILE:~0,-4%_clipped.las

:: allows you to run the script from other folders
::set PATH=%PATH%;C:\Programme\LASTools\bin;
set PATH=%PATH%;C:\LASTools\bin;


::
:: do the actual processing
::

:: clip and keep inside for thinning
lasclip -i %1 ^
        -poly %SHAPEFILE% ^
        -o %OUTFILE%


:: replace System / Software tags in output file

lasinfo -i %OUTFILE% ^
        -set_system_identifier "svGeo photogrammetry" ^
        -set_generating_software "svGeo las_pipe"