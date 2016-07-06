#!/bin/sh
set -ev

rm -rf mingw32
make distclean || true

echo "COMPILING..."

./configure --prefix=`pwd`/mingw32 --host=i686-w64-mingw32 \
    --enable-shared --disable-static --without-matlab --without-octave \
    --without-python --without-guile --without-threadlocal \
    && make -j4 && make install

echo "POST-PROCESSING..."

nlopt_vers=`grep PACKAGE_VERSION config.h | cut -d" " -f3 | tr -d \"`

# .def file
cd mingw32/bin
for dll in *.dll; do
    def=`basename $dll .dll`.def
    echo "LIBRARY $dll" > $def
    echo EXPORTS >> $def
    i686-w64-mingw32-gcc-nm $dll | grep ' T _' | sed 's/.* T _//' | egrep 'nlopt|nlo_' >> $def
done
cd ../..

# header file
perl -pi -e 's,^ * #define NLOPT_DLL,*/\n#define NLOPT_DLL\n/*,' mingw32/include/nlopt.h
rm -f mingw32/include/nlopt.h.bak

# readme file
cat > mingw32/README-WINDOWS <<EOF
This .zip archive contains DLL libraries and the associated header (.h)
and module-definition (.def) files of NLopt compiled for Win32.

In order to link to this .dll files from Visual C++, you need to
create a .lib "import libraries" for it, and can do so with the "lib"
command that comes with VC++.  In particular, run:

    cd bin
    lib /def:libnlopt-0.def

Remember to add the "bin" directory to the PATH environment variable
if you are dynamically linking against the library DLL
(this applies to both the MATLAB and Python extensions):

    set PATH=%PATH%;C:\path\to\nlopt\bin

To compile the MATLAB plugin, use the MATLAB "mex" compiler on the file
nlopt_optimize.c (being sure to link to the libnlopt DLL) in the matlab
subdirectory.

    cd matlab
    mex -largeArrayDims -output nlopt_optimize -I"..\include"
        nlopt_optimize-mex.c -L"..\bin" -llibnlopt-0

To build the Python plugin (assuming that you have Python and Numpy
installed), do:

    cd python
    python setup.py build_ext --inplace

They were compiled by the GNU C compiler for MinGW, specifically:
EOF
i686-w64-mingw32-gcc --version | head -1 >> mingw32/README-WINDOWS

# matlab mex extension
mkdir -p mingw32/matlab
cp octave/*.m mingw32/matlab/
cp octave/nlopt_optimize-mex.c mingw32/matlab/nlopt_optimize.c

# python extension
mkdir -p mingw32/python
cp swig/nlopt.py swig/nlopt-python.cpp mingw32/python/
cat > mingw32/python/setup.py <<EOF
from distutils.core import setup, Extension
import numpy

nlopt_module = Extension('_nlopt',
                         sources = ['nlopt-python.cpp'],
                         libraries = ['libnlopt-0'],
                         include_dirs = ['../include'],
                         library_dirs = ['../bin'])

setup (name         = 'nlopt',
       version      = '${nlopt_vers}',
       author       = "Steven G. Johnson",
       author_email = "stevenj@alum.mit.edu",
       url          = "http://ab-initio.mit.edu/nlopt/",
       description  = """NLopt nonlinear-optimization library""",
       license      = "LGPL, MIT",
       ext_modules  = [nlopt_module],
       py_modules   = ["nlopt"],
       include_dirs = ['.', numpy.get_include()],
       )
EOF

# extra files
cp COPYING COPYRIGHT NEWS README mingw32/

echo "PACKAGING..."

zipfile=nlopt-${nlopt_vers}-dll32.zip
rm -f $zipfile
pushd mingw32/ && zip -v -9 -r ../$zipfile . -x lib/\* share/\* && popd
