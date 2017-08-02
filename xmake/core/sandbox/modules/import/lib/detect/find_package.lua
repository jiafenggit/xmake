--!The Make-like Build Utility based on Lua
--
-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements.  See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership.  The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- 
-- Copyright (C) 2015 - 2017, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        find_package.lua
--

-- define module
local sandbox_lib_detect_find_package = sandbox_lib_detect_find_package or {}

-- load modules
local os                = require("base/os")
local path              = require("base/path")
local utils             = require("base/utils")
local table             = require("base/table")
local option            = require("base/option")
local config            = require("project/config")
local project           = require("project/project")
local raise             = require("sandbox/modules/raise")
local import            = require("sandbox/modules/import")
local cache             = require("sandbox/modules/import/lib/detect/cache")
local pkg_config        = import("lib.detect.pkg_config")

-- find package from package directories
function sandbox_lib_detect_find_package._find_from_packagedirs(name, opt)

    -- get package path (.e.g name.pkg) in the package directories
    local packagepath = nil
    for _, dir in ipairs(table.wrap(opt.packagedirs)) do
        local p = path.join(dir, name .. ".pkg")
        if os.isdir(p) then
            packagepath = p
            break
        end
    end
    if not packagepath then
        return 
    end

    -- get package file (.e.g name.pkg/xmake.lua)
    local packagefile = path.join(packagepath, "xmake.lua")
    if not os.isfile(packagefile) then
        return 
    end

    -- get interpreter
    local interp = project.interpreter()

    -- register filter handler
    interp:filter():register("find_package_" .. name, function (variable)
 
        -- init maps
        local maps = 
        {
            arch        = opt.arch
        ,   plat        = opt.plat
        ,   mode        = opt.mode
        }

        -- get variable
        return maps[variable]
    end)

    -- load the package from the the package file
    local packageinfos, errors = interp:load(packagefile, "option", true, true)
    if not packageinfos then
        raise(errors)
    end

    -- clear filter handler
    interp:filter():register("find_package_" .. name, nil)

    -- get package info
    local packageinfo = packageinfos[name]
    if not packageinfo then
        return 
    end

    -- get linkdirs
    local linkdirs = {}
    for _, linkdir in ipairs(table.wrap(packageinfo.linkdirs)) do
        table.insert(linkdirs, path.join(packagepath, linkdir))
    end
    if #linkdirs == 0 then
        return 
    end

    -- import find_library
    local find_library = import("lib.detect.find_library")

    -- find library 
    local result = nil
    for _, link in ipairs(table.wrap(packageinfo.links)) do
        local libinfo = find_library(link, linkdirs)
        if libinfo then
            result          = result or {}
            result.links    = table.join(result.links or {}, libinfo.link)
            result.linkdirs = table.join(result.linkdirs or {}, libinfo.linkdir)
        end
    end

    -- inherit other package info
    if result then
        result.includedirs = {}
        for _, includedir in ipairs(table.wrap(packageinfo.includedirs)) do
            table.insert(result.includedirs, path.join(packagepath, includedir))
        end
        for _, infoname in ipairs({"defines", "languages", "warnings"}) do
            result[infoname] = packageinfo[infoname]
        end
    end

    -- ok?
    return result
end

-- find package from repositories
function sandbox_lib_detect_find_package._find_from_repositories(name, opt)

    -- TODO in repo branch
end

-- find package from modules (detect.packages.find_xxx)
function sandbox_lib_detect_find_package._find_from_modules(name, opt)

    -- "detect.packages.find_xxx" exists?
    local find_package = import("detect.packages.find_" .. name, {try = true})
    if find_package then
        return find_package(opt)
    end
end

-- find package from pkg-config
function sandbox_lib_detect_find_package._find_from_pkg_config(name, opt)
    return import("lib.detect.pkg_config").find(name, opt)
end

-- find package from system directories
function sandbox_lib_detect_find_package._find_from_systemdirs(name, opt)

    -- cannot get the version of package
    if opt.version then
        return 
    end

    -- add default search includedirs on pc host
    local includedirs = table.wrap(opt.includedirs)
    if opt.plat == "linux" or opt.plat == "macosx" then
        table.insert(includedirs, "/usr/local/include")
        table.insert(includedirs, "/usr/include")
        table.insert(includedirs, "/opt/local/include")
        table.insert(includedirs, "/opt/include")
    end

    -- add default search linkdirs on pc host
    local linkdirs = table.wrap(opt.linkdirs)
    if opt.plat == "linux" or opt.plat == "macosx" then
        table.insert(linkdirs, "/usr/local/lib")
        table.insert(linkdirs, "/usr/lib")
        table.insert(linkdirs, "/opt/local/lib")
        table.insert(linkdirs, "/opt/lib")
        if opt.plat == "linux" and opt.arch == "x86_64" then
            table.insert(linkdirs, "/usr/local/lib/x86_64-linux-gnu")
            table.insert(linkdirs, "/usr/lib/x86_64-linux-gnu")
        end
    end

    -- attempt to get links from pkg-config
    local pkginfo = nil
    local links = table.wrap(opt.links)
    if #links == 0 then
        pkginfo = import("lib.detect.pkg_config").info(name)
        if pkginfo then
            links = table.wrap(pkginfo.links)
        end
    end

    -- uses name as links directly .e.g libname.a
    if #links == 0 then
        links = table.wrap(name)
    end

    -- import find_path and find_library
    local find_path    = import("lib.detect.find_path")
    local find_library = import("lib.detect.find_library")

    -- find library 
    local result = nil
    for _, link in ipairs(links) do
        local libinfo = find_library(link, linkdirs)
        if libinfo then
            result          = result or {}
            result.links    = table.join(result.links or {}, libinfo.link)
            result.linkdirs = table.join(result.linkdirs or {}, libinfo.linkdir)
        end
    end

    -- find includes
    for _, include in ipairs(table.wrap(opt.includes)) do
        local includedir = find_path(include, includedirs)
        if includedir then
            result             = result or {}
            result.includedirs = table.join(result.includedirs or {}, includedir)
        end
    end
    for _, include in ipairs({name .. "/" .. name .. ".h", name .. ".h"}) do
        local includedir = find_path(include, includedirs)
        if includedir then
            result             = result or {}
            result.includedirs = table.join(result.includedirs or {}, includedir)
            break
        end
    end

    -- not found? only add links
    if not result and pkginfo and pkginfo.links then
        result = {links = pkginfo.links}
    end

    -- ok
    return result
end

-- find package
function sandbox_lib_detect_find_package._find(name, opt)

    -- init find scripts
    local findscripts = 
    {
        sandbox_lib_detect_find_package._find_from_packagedirs
    ,   sandbox_lib_detect_find_package._find_from_repositories
    ,   sandbox_lib_detect_find_package._find_from_modules
    }

    -- find package from the current host platform
    if opt.plat == os.host() and opt.arch == os.arch() then
        table.insert(findscripts, sandbox_lib_detect_find_package._find_from_pkg_config)
        table.insert(findscripts, sandbox_lib_detect_find_package._find_from_systemdirs)
    end

    -- find it
    local result = nil
    for _, find in ipairs(findscripts) do
        result = find(name, opt)
        if result then
            break
        end
    end

    -- remove repeat
    if result then
        result.linkdirs    = table.unique(result.linkdirs)
        result.includedirs = table.unique(result.includedirs)
    end

    -- ok?
    return result
end

-- find package 
--
-- @param name      the package name
-- @param opt       the package options. 
--                  e.g. { verbose = false, force = false, plat = "iphoneos", arch = "arm64", mode = "debug", version = "1.0.1", 
--                     linkdirs = {"/usr/lib"}, includedirs = "/usr/include", links = {"ssl"}, includes = {"ssl.h"}
--                     packagedirs = {"/tmp/packages"}}
--
-- @return          {links = {"ssl", "crypto", "z"}, linkdirs = {"/usr/local/lib"}, includedirs = {"/usr/local/include"}}
--
-- @code 
--
-- local package = find_package("openssl")
-- local package = find_package("openssl", {version = "1.0.1"})
-- local package = find_package("openssl", {plat = "iphoneos"})
-- local package = find_package("openssl", {linkdirs = {"/usr/lib", "/usr/local/lib"}, includedirs = "/usr/local/include", version = "1.0.1"})
-- local package = find_package("openssl", {linkdirs = {"/usr/lib", "/usr/local/lib", links = {"ssl", "crypto"}, includes = {"ssl.h"}})
-- 
-- @endcode
--
function sandbox_lib_detect_find_package.main(name, opt)

    -- init options
    opt = opt or {}
    opt.plat = opt.plat or config.get("plat") or os.host()
    opt.arch = opt.arch or config.get("arch") or os.arch()
    opt.mode = opt.mode or config.get("mode") 

    -- init cache key
    local key = "find_package_" .. opt.plat .. "_" .. opt.arch

    -- attempt to get result from cache first
    local cacheinfo = cache.load(key) 
    local result = cacheinfo[name]
    if result ~= nil and not opt.force then
        return utils.ifelse(result, result, nil)
    end

    -- find package
    result = sandbox_lib_detect_find_package._find(name, opt) 

    -- cache result
    cacheinfo[name] = utils.ifelse(result, result, false)

    -- save cache info
    cache.save(key, cacheinfo)

    -- trace
    if opt.verbose or option.get("verbose") then
        if result then
            utils.cprint("checking for the %s ... ${green}ok", name)
        else
            utils.cprint("checking for the %s ... ${red}no", name)
        end
    end

    -- ok?
    return result
end

-- return module
return sandbox_lib_detect_find_package
