::
:: Batch script to transform las file to a comma separated ASCII xyz file (e.g. for Civil3D)
::
:: Input is LAS file
:: Output is a comma separated ASCII XYZ file with the same points
::
:: Parameters:
::
:: none
::
:: USAGE: las_to_xyz_comma_separated.bat mypointcloud.las
::
::
:: Processing steps:
:: las2text transform las to ASCII xyz
::
:: Steffen Vogt, 2020-07-22

echo off

::
:: specify parameters
::

:: get the input las file name for ouptut file name generation
set INFILE=%1
set OUTFILE=%INFILE:~0,-4%.txt

:: allows you to run the script from other folders
::set PATH=%PATH%;C:\Programme\LASTools\bin;
set PATH=%PATH%;C:\LASTools\bin;


:: Write ASCII xyz file
las2txt -i %INFILE% ^
        -o %OUTFILE% ^
        -parse xyz ^
        -sep comma ^
        -cpu64

echo finished creating %OUTFILE%
