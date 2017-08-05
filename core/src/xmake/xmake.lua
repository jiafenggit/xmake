-- add target
target("xmake")

    -- make as a static library
    set_kind("static")

    -- add deps
    add_deps("sv", "luajit")

    -- add defines
    add_defines("__tb_prefix__=\"xmake\"")

    -- set the auto-generated config.h
    set_config_header("$(projectdir)/xmake.config.h", {prefix = "XM_CONFIG"})

    -- set the object files directory
    set_objectdir("$(buildir)/.objs")

    -- add includes directory
    add_includedirs("$(projectdir)", "$(buildir)/luajit", "$(buildir)/include")

    -- add packages
    add_packages("tbox", "base")

    -- add the common source files
    add_files("**.c") 
       
    -- add cfunc
    add_cfunc("API", "readline", nil, {"readline/readline.h"}, "readline")

    if is_mode("coverage") then
        add_cxflags("-coverage", "-fprofile-arcs", "-ftest-coverage")
    end
