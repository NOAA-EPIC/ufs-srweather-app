
help([[
This module loads libraries for building the UFS SRW App in
a singularity container
]])

whatis([===[Loads libraries needed for building the UFS SRW App in singularity container ]===])

prepend_path("MODULEPATH","/opt/spack-stack/spack/share/spack/modules/linux-ubuntu20.04-skylake")
prepend_path("MODULEPATH","/opt/spack-stack/envs/release/public-v2.1.0/install/modulefiles/Core")
prepend_path("PATH","/opt/miniconda/envs/regional_workflow/bin")
load("cmake/3.22.1")
load("intel-oneapi-compilers/2022.1.0")
load("intel-oneapi-mpi/2021.6.0")
load("stack-intel")
load("stack-intel-oneapi-mpi")
load("bacio/2.4.1")
load("bufr/11.7.0")
load("ca-certificates-mozilla/2022-07-19")
load("cmake/3.22.1")
load("crtm/2.3.0")
load("curl/7.49.1")
load("ecbuild/3.6.5")
load("esmf/8.3.0b09")
load("fms/2022.01")
load("g2/3.4.5")
load("g2tmpl/1.10.0")
load("gftl-shared/1.5.0")
load("git/2.25.1")
load("git-lfs/2.9.2")
load("hdf5/1.12.1")
load("ip/3.3.3")
load("jasper/2.0.25")
load("libjpeg/2.1.0")
load("libpng/1.6.37")
load("mapl/2.22.0-esmf-8.3.0b09-esmf-8.3.0")
load("ncio/1.1.2")
load("nemsio/2.5.4")
load("netcdf-c/4.7.4")
load("netcdf-fortran/4.5.4")
load("openblas/0.3.19")
load("parallel-netcdf/1.12.2")
load("parallelio/2.5.2")
load("patchelf/0.15.0")
load("pkg-config/0.29.2")
load("py-cython/0.29.30")
load("py-numpy/1.22.3")
load("py-pip/22.1.2")
load("py-setuptools/63.0.0")
load("py-wheel/0.37.1")
load("sfcio/1.4.1")
load("sigio/2.3.2")
load("sp/2.3.3")
load("stack-python/3.8.10")
load("w3emc/2.9.2")
load("w3nco/2.4.1")
load("wgrib2/2.0.8")
load("wrf-io/1.2.0")
load("yafyaml/0.5.1")
load("zlib/1.2.12")

setenv("CMAKE_C_COMPILER","mpiicc")
setenv("CMAKE_CXX_COMPILER","mpicxx")
setenv("CMAKE_Fortran_COMPILER","mpif90")
setenv("CMAKE_Platform","singularity.gnu")
