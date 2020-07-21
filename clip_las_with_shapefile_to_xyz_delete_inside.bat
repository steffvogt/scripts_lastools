::
:: Batch script for deleting points inside polygon(s) defined by a shapefile and output las file and xyz file (e.g. for Civil3D)
::
:: Input is LAS file from e.g. pix4D and a shapefile with polygon(s) of the clipping area
:: Output is one single LAS file where the points inside the polygon(s) have been deleted
:: and a comma separeted ASCII XYZ file with the same points
::
:: Parameters:
::
:: none
::
:: USAGE: clip_las_with_shapefile_to_xyz_delete_inside.bat mypointcloud.las mypolygonshapefile.shp
::
::
:: Processing steps:
:: lasclip creates point cloud with points only outside the clipping polygon(s)
::
:: Steffen Vogt, 2020-07-21

echo off

::
:: specify parameters
::

:: get the input las file name for ouptut file name generation
set INFILE=%1

:: get the input shape file name
set SHAPEFILE=%2

set OUTFILE=%INFILE:~0,-4%_clipped.las

:: allows you to run the script from other folders
::set PATH=%PATH%;C:\Programme\LASTools\bin;
set PATH=%PATH%;C:\LASTools\bin;


::
:: do the actual processing
::

:: clip and keep points outside of polygons
lasclip -i %1 ^
        -interior ^
        -poly %SHAPEFILE% ^
        -o %OUTFILE% ^
        -cpu64


:: replace System / Software tags in output las file

lasinfo -i %OUTFILE% ^
        -set_system_identifier "svGeo photogrammetry" ^
        -set_generating_software "svGeo las_pipe"

:: Write ASCII xyz file
las2txt -i %OUTFILE% ^
        -o %OUTFILE%.txt ^
        -parse xyz ^
        -sep comma ^
        -cpu64