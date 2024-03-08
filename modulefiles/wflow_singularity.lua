help([[
This module loads python environement for running the UFS SRW App in
a singularity container
]])

whatis([===[Loads libraries needed for running the UFS SRW App in a singularity container]===])
load("set_pythonpath")

prepend_path("MODULEPATH","/lustre/rocoto/modulefiles")
load("rocoto/1.3.6")

append_path("MODULEPATH","/lustre/miniconda3/modulefiles")
load("miniconda3")

setenv("PROJ_LIB","/lustre/miniconda3/4.12.0/envs/regional_workflow/share/proj")
append_path("PATH","/lustre/miniconda3/4.12.0/envs/regional_workflow/bin")

if mode() == "load" then
   LmodMsgRaw([===[Please do the following to activate conda:
       > conda activate workflow_tools
]===])
end
