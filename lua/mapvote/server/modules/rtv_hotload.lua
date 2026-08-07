--[[-----------------
    Init
-------------------]]
local Nominate = {} -- functions table
hook.Add("MapVote_ConfigValueChanged", "RunEverythingOnEnableNominationsToggle", function(key, to, from)
    if key ~= "EnableNomination" then return end
    local FilePath = debug.getinfo(function() end).short_src
    local ThisFile = string.match(FilePath, "lua/(.+)")
    include(ThisFile)
end)

_G["NOMINATE_HOOKS"] = _G["NOMINATE_HOOKS"] or {}
if MapVote.GetConfig().EnableNomination == false then
    for i = #NOMINATE_HOOKS, 1, -1 do
        local hookname = NOMINATE_HOOKS[i][1]
        local identifier = NOMINATE_HOOKS[i][2]
        hook.Remove(hookname, identifier)
        print("removed hook ", hookname, identifier)
        NOMINATE_HOOKS[hookname] = nil
    end
    return
end

function Nominate.AddHook(hookname, identifier, func) -- so that the hooks can be cleared easily when conf.EnableNomination is set to false
    if not hookname then
        error("no hookname")
    elseif not identifier then
        error("no identifier")
    end

    hook.Add(hookname, identifier, func)
    for i = 1, #NOMINATE_HOOKS do
        if NOMINATE_HOOKS[i][1] == hookname and NOMINATE_HOOKS[i][2] == identifier then -- the hook is already in the table, stop spamming entries into the table
            return
        end
    end

    NOMINATE_HOOKS[#NOMINATE_HOOKS + 1] = {hookname, identifier}
end

local ENV = file.Exists("mapvote/ENV.json", "DATA")
if not ENV then
    file.Write("mapvote/ENV.json", util.TableToJSON({
        SERVER_URL = "", -- https://gamecp.physgun.com/server/XXXXXXXX <--
        ACCOUNTTOKEN = "" -- get this at https://gamecp.physgun.com/account/security and paste it here
    }))
end

ENV = util.JSONToTable(file.Read("mapvote/ENV.json", "DATA"))
local SERVER_TOKEN = ENV.ACCOUNTTOKEN -- this is used to delete lingering hotloaded gmas in cache/scrds and steam_cache
local SERVER_URL = ENV.SERVER_URL -- this is used for the api links
local WISPED = (SERVER_TOKEN and SERVER_TOKEN ~= "") and (SERVER_URL and SERVER_URL ~= "") -- assumption on if the player is able to use WISP (Notion) api properly
CAMI.RegisterPrivilege{
    Name = "HotloadMap",
    MinAccess = "superadmin"
}

--[[-----------------
    Useful functions
-------------------]]
local function DelayPrintMessage(HUDTYPE, message)
    timer.Simple(0, function() PrintMessage(HUDTYPE, message) end)
end

local PLAYERMETA = FindMetaTable("Player")
function PLAYERMETA:DelayPrintMessage(HUDTYPE, message)
    if not IsValid(self) then return end
    timer.Simple(0, function() self:PrintMessage(HUDTYPE, message) end)
end

local matchedDirs = {}
local function recurseListContents(path, first) -- this is from example #2, won't let me link it properly https://wiki.facepunch.com/gmod/file.Find#example
    -- do not fill in arg[2]! that is for the function itself to fill (could do a local bool above the function instead, but it fulfills its purpose, whatever, maybe later).
    local files, dirs = file.Find(path .. "*", "DATA")
    local matchedFiles = {}
    matchedDirs = (first == nil and {}) or matchedDirs
    for _, v in ipairs(files) do
        local fullPath = path .. v
        table.insert(matchedFiles, fullPath)
    end

    for _, dir in ipairs(dirs) do
        local subFiles = select(1, recurseListContents(path .. dir .. "/", false))
        for _, filepath in ipairs(subFiles) do
            table.insert(matchedFiles, filepath)
        end

        table.insert(matchedDirs, path .. dir)
    end
    return matchedFiles, matchedDirs
end

local function DeleteDirectory(filepath)
    local PathsToDelete, DirsToDelete = recurseListContents(filepath)
    for _, path in ipairs(PathsToDelete) do
        file.Delete(path)
        --print("deleted " .. path)
    end

    for _, path in ipairs(DirsToDelete) do -- you cant delete a directory until all of its subfolders and subfiles are deleted, apparently
        file.Delete(path)
        --print("deleted dir " .. path)
    end
end

--[[-----------------
    Rest
-------------------]]
-- this requires my fork of raphael's gma-writer to work https://github.com/greyliterature/gmod-lua-gma-writer/blob/main/gma.lua
-- ill have to add it to the modules folder probably. 
-- i havent asked for permission from raphael to put his gma-writer code directly in another repo so when this concept is closer to being finished i will do that.
-- do later:
-- disable hotloading by default with a convar and only run anything in here if its set to 1
require("workshop") -- https://github.com/WilliamVenner/gmsv_workshop
-- this is tested with 32 bit windows gmsv_workshop on a p2p server
--
-- maybe this json can be reduced or accounted for in the gma parser itself. (not very much space but still unnecessary)
local addonjson = [[ 
    {
        "title": "My Server Content",
        "type": "ServerContent",
        "tags": [
            "roleplay",
            "realism"
        ],
        "ignore": [
            "placeholder",
        ]
    }
]]
local UnwhitelistedExtensions = {
    -- these arent part of the file.write whitelist, and will cause bugs if they arent handled for / bypassed
    -- only 2 unwhitelisted extensions are accounted for. DuplicatedToStrippedGMA will probably break if theres more unwhitelisted extensions not accounted for, because
    -- of how the successrequirement variable works in there, so
    -- fix that later
    "bsp",
    "pcf",
    "ain",
}

local Blacklist = {
    -- NEVER file.write these extensions into the stripped gma.
    ["lua"] = true,
    xml = true,
    csv = true,
    json = true,
    vcs = true,
    dat = true,
    png = true,
    properties = true,
    ttf = true,
    nav = true,
}

local function IsExtensionBlacklisted(extension)
    return Blacklist[extension]
end

local DiskLimit, DiskUsed, DiskLeft = nil, nil, nil
local function DuplicateToStrippedGMA(filepath, callback) -- rewrite the gma but without all the lua
    -- this makes a folder in data/strippedhotloadgmas of the extracted gma
    -- then it takes the stripped, extracted contents and packs it into another gma
    -- this is done so that the server can mount any map gma it wants without getting backdoored by random lua in the addon downloaded with steamworks.DownloadUGC
    -- this also seems very inefficient. it parses the gma, rewrites it, then packs it into another gma.
    -- could probably do something with file:meta() functions to not be so redundant
    local wsid = string.match(filepath, ".*/(%d+)%.gma$")
    local NewGMAPath = "strippedhotloadgmas/" .. wsid
    file.CreateDir(NewGMAPath)
    file.Write(NewGMAPath .. "/" .. "addon.json", addonjson)
    local files = GMA.Read(filepath, false, "GAME").Files
    local successrequirement = table.Count(files)
    for k, tbl in ipairs(files) do
        if IsExtensionBlacklisted(string.GetExtensionFromFilename(tbl.Name)) then successrequirement = successrequirement - 1 end
    end

    local successes = 0
    local ExtensionsToBypass = {}
    for k, tbl in ipairs(files) do
        local OriginalPath = tbl.Name
        local DirectoryPath = string.match(OriginalPath, "^(.*)/[^/]+$")
        print("Considering writing " .. OriginalPath)
        --[[
        if string.lower(string.sub(DirectoryPath, 1, 3)) == "lua" then
            print("not duplicating " .. DirectoryPath)
            successrequirement = successrequirement - 1
            continue
        end
        --]]
        if IsExtensionBlacklisted(string.GetExtensionFromFilename(OriginalPath)) then
            print("not duplicating " .. OriginalPath .. ", blacklisted extension")
            --successrequirement = successrequirement - 1
            continue
        end

        file.CreateDir(NewGMAPath .. "/" .. DirectoryPath)
        local filename = NewGMAPath .. "/" .. OriginalPath
        for i = 1, #UnwhitelistedExtensions do
            local extension = UnwhitelistedExtensions[i]
            if string.EndsWith(OriginalPath, extension) == true then -- fix for .bsp, .pcf, etc not being in file.write whitelist
                --continue
                OriginalPath = OriginalPath .. ".txt"
                ExtensionsToBypass[extension .. ".txt"] = true
                filename = filename .. ".txt"
                print("bypassing " .. filename)
            end
        end

        local succ = file.Write(filename, "")
        print("Writing " .. filename)
        if succ then
            print("Successfully wrote " .. filename)
            local f = file.Open(NewGMAPath .. "/" .. OriginalPath, "wb", "DATA")
            f:Write(tbl.Content)
            f:Close()
            successes = successes + 1
            if successes == successrequirement then -- create gma when every single file is done
                -- note: gma.create uses input relative to DATA, but output relative to GAME
                if file.Exists(NewGMAPath .. ".gma", "DATA") == true then -- if the GMA file already exists, then it's probably safe to use that instead of making a new gma (it also prevents errors, because game.mountgma makes the file.open in gma.create -> gma.build() not work)
                    print("GMA already mounted, calling back with old gma")
                    callback("data/" .. NewGMAPath .. ".gma")
                    return
                end

                GMA.Create(NewGMAPath .. ".gma", "data" .. "/" .. NewGMAPath, true, false, function(gmapath)
                    print("GMA created, cleaning up work folder strippedhotloadgmas/" .. wsid)
                    DeleteDirectory("strippedhotloadgmas/" .. wsid)
                    local NewGMASize = file.Size(string.Replace(gmapath, "data/", ""), "DATA")
                    DiskLeft = DiskLeft - NewGMASize
                    print("New GMA size: " .. NewGMASize .. ", Disk left: " .. DiskLeft)
                    callback(gmapath)
                    DelayPrintMessage(HUD_PRINTTALK, "Made " .. gmapath)
                end, ExtensionsToBypass)
            end
        else
            ErrorNoHaltWithStack("Failed writing " .. NewGMAPath .. "/" .. OriginalPath .. "\n")
            callback(nil) -- fail! callback to HotloadMap and tell it to just load the second most voted (non hotloaded) map.
        end
        --print(DirectoryPath)
        --]]
    end
    --callback(nil)
    -- this callback(nil) was here before and was probably important so im leaving it commented here. revisit later
end

local HotloadedMaps = {}
--[[
local function FindMapWorkshopID(mapname) -- unused, should make initpostentity use this, move the sql stuff into here and just call that
    for k, v in ipairs(engine.GetAddons()) do
        print(k)
        PrintTable(v)
    end
end
--]]
--FindMapWorkshopID("ap_aerowalk")
local function WriteHotloadedMapToSQL(mapname, wsid) -- map name with ".bsp" by the way
    local firstoperation = sql.QueryTyped("CREATE TABLE IF NOT EXISTS hotloaded_maps (mapname TEXT, wsid TEXT)")
    if firstoperation == false then
        error("first operation failed" .. sql.LastError())
        return
    end

    local secondoperation = sql.QueryTyped("INSERT INTO hotloaded_maps (mapname, wsid) VALUES (?, ?)", mapname, wsid)
    if secondoperation == false then
        error("second operation failed" .. sql.LastError())
        return
    end

    print("successfully wrote " .. mapname .. ", " .. wsid .. " to sql")
end

local DownloadedPathsCache = {}
local Queued = {} -- wsids that are currently being downloaded, prevents someone from spamming !nominate wsid and making the map download multiple times
function steamworks.DownloadUGC_CACHED(wsid, callback)
    if DownloadedPathsCache[wsid] then
        print("returning cached wsid: " .. wsid .. ", cached path: " .. DownloadedPathsCache[wsid])
        callback(DownloadedPathsCache[wsid], _)
        return
    end

    if Queued[wsid] then
        print(wsid .. " is already queued for download, returning")
        return
    end

    Queued[wsid] = true
    sql.QueryTyped("INSERT INTO hotloaded_maps (mapname, wsid) VALUES (?, ?)", "", wsid) -- always write the wsid so that it gets deleted later
    print("Downloading new ugc " .. wsid)
    steamworks.DownloadUGC(wsid, function(path, fileobject)
        DownloadedPathsCache[wsid] = path
        Queued[wsid] = nil
        callback(path, fileobject)
    end)
end

local AlreadyMountedWSIDs = {} -- prevent errors in GMA.create -> GMA.build about it complaining about not being able to open (mounted?) gma files
local function HotloadMap(wsid, callback) -- this should only mount if the map is voted on, not always
    print("Hotloading " .. wsid)
    steamworks.DownloadUGC_CACHED(wsid, function(path, fileobject)
        -- the file
        if not path then error("No path for " .. wsid) end
        if WISPED == false then print("remember to delete the original gma file in " .. path .. ".\nthis function does not delete it by itself. will figure out a way to do this through api or something eventually.") end
        -- inconvenient, solve this later
        -- maybe something can be done with the fileobject given, not sure
        DuplicateToStrippedGMA(path, function(gmapath)
            if not gmapath then
                ErrorNoHaltWithStack("gmapath is nil")
                -- at this point you should be giving up and loading another map, or cancelling the RTV. 
                callback(false)
                return
            end

            --DelayPrintMessage(HUD_PRINTTALK, "Made stripped GMA at " .. gmapath)
            if AlreadyMountedWSIDs[wsid] then
                print(wsid .. " was already mounted, returning")
                return
            end

            print("Mounting " .. wsid)
            local succ, files = game.MountGMA(gmapath)
            if succ == true then
                AlreadyMountedWSIDs[wsid] = true
                DelayPrintMessage(HUD_PRINTTALK, "Mounted stripped GMA")
                for _, filename in ipairs(files) do
                    if string.EndsWith(filename, ".bsp") then --
                        filename = string.GetFileFromFilename(filename)
                        WriteHotloadedMapToSQL(filename, wsid)
                        HotloadedMaps[filename] = wsid
                        DelayPrintMessage(HUD_PRINTTALK, "Mounted " .. filename)
                    end
                end

                callback(true)
            else
                error("failed to mount GMA")
                callback(false)
            end
        end)
    end)
end

Nominate.AddHook("PlayerSay", "Hotload Map Command", function(sender, text, teamChat)
    if not string.StartsWith(text, "!hotload") then return end
    args = string.Explode(" ", text) -- !command -> 123, true, false <-
    table.remove(args, 1)
    CAMI.PlayerHasAccess(sender, "HotloadMap", function(b, _)
        -- From https://github.com/FPtje/FSpectate/blob/6ea5ae6e1b60fa8f1f848a2588db7225aea4dcd4/lua/fspectate/sv_init.lua#L66
        if not b then
            sender:ChatPrint("Not allowed to hotload maps!")
            return
        end

        local wsid = args[1]
        steamworks.FileInfo(wsid, function(data)
            -- check if the wsid is valid
            if data and data.error then
                sender:DelayPrintMessage(HUD_PRINTTALK, "Workshop ID errored, probably invalid")
            elseif not data then
                sender:DelayPrintMessage(HUD_PRINTTALK, "Must provide a valid workshop ID")
            else
                print("Checking filesize of new " .. wsid)
                if data then
                    local conf = MapVote.GetConfig()
                    if WISPED == true and DiskLeft - data.size < conf.NominateByteThreshold then
                        print(wsid .. " is " .. (conf.NominateByteThreshold - DiskLeft - data.size) .. " over the disk threshold, returning")
                        return
                    elseif WISPED == true then
                        DiskLeft = DiskLeft - data.size
                        print("Disk left: " .. DiskLeft)
                    end
                else
                    print("No data in FileInfo() for " .. wsid)
                end

                Nominate.GetMapsFromAddon(wsid, function(PossibleMaps, firstmap)
                    if table.Count(PossibleMaps) - 1 == 0 then sender:DelayPrintMessage(HUD_PRINTTALK, "That addon does not have any maps!") end
                    HotloadMap(wsid, function(succ) return end)
                end)
            end
        end)
        return
    end)
end)

local function Clear_app_workshop_OfLingeringWSID(wsid)
    local appworkshop_4000 = nil
    local HTTPTable = {
        method = "GET",
        url = "https://gamecp.physgun.com/api/client/servers/" .. SERVER_URL .. "/files/read",
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/vnd.wisp.v1+json",
            ["Authorization"] = "Bearer " .. SERVER_TOKEN,
        },
        parameters = {
            ["path"] = "/steam_cache/appworkshop_4000.acf"
        },
        failed = function(reason) print("HTTP request failed", reason) end,
        success = function(code, body, headers)
            if code ~= 200 then
                print("Bad response: ", code, body)
            else
                appworkshop_4000 = util.JSONToTable(body).content
                local copy = ""
                local WithinTable = false
                for linenumber, line in ipairs(string.Split(appworkshop_4000, "\n")) do
                    if string.find(line, wsid) then --string.find(line, "\\\"" .. wsid .. "\\\"") == true then
                        WithinTable = true
                        CountSinceCloser = 0
                    end

                    if string.find(line, "}", nil, nil, true) and WithinTable == true then -- closer
                        line = "" --line .. "VERYEASYTOSPOTTEXT1234567890"
                        WithinTable = false
                    end

                    if WithinTable == true then
                        line = "" --line .. "VERYEASYTOSPOTTEXT1234567890"
                    end

                    copy = copy .. "\n" .. line
                end

                if copy ~= "" then
                    HTTP({
                        method = "POST",
                        url = "https://gamecp.physgun.com/api/client/servers/" .. SERVER_URL .. "/files/write",
                        headers = {
                            ["Content-Type"] = "application/json",
                            ["Accept"] = "application/vnd.wisp.v1+json",
                            ["Authorization"] = "Bearer " .. SERVER_TOKEN,
                        },
                        parameters = {
                            ["path"] = "/steam_cache/appworkshop_4000.acf",
                            ["content"] = copy,
                        },
                        failed = function(reason) print("HTTP request failed", reason) end,
                        success = function(code_2, body_2, headers_2)
                            if code ~= 200 then
                                print("Bad response: ", code, body)
                            else
                                print("Overwrote app_workshop for " .. wsid .. "successfully")
                            end
                        end,
                    })
                end
            end
        end,
    }

    HTTP(HTTPTable)
end

local color_red = Color(255, 0, 0)
local function DeleteLingeringHotloadedGMAs()
    if RealTime() > 30 then
        print("Not deleting, server did not recently start.")
        return
    end

    if WISPED ~= true then
        local FilePath = debug.getinfo(function() end).short_src
        MsgC(color_red, "SERVER_URL / ACCOUNTTOKEN not provided, returning.\nThis means you will have to manually delete the gma files accumulated in cache/scrds and steam_cache, since the script can't do it for you.\nRead the top of the file @ " .. FilePath .. " for links on how to get them\n")
        return
    end

    local HTTPTable = {
        method = "POST",
        url = "https://gamecp.physgun.com/api/client/servers/" .. SERVER_URL .. "/files/delete",
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/vnd.wisp.v1+json",
            ["Authorization"] = "Bearer " .. SERVER_TOKEN,
        },
        parameters = {},
        failed = function(reason) print("HTTP request failed", reason) end,
        success = function(code_2, body_2, headers_2)
            if code_2 == 204 then
                print("Deleted successfully")
            else
                print("Bad response: ", code_2, body_2)
            end
        end,
    }

    local HotloadedWSIDsQuery = sql.QueryTyped("SELECT DISTINCT wsid FROM hotloaded_maps")
    if HotloadedWSIDsQuery ~= false then
        local i = 1
        local step = 1
        if table.Count(HotloadedWSIDsQuery) > 0 then
            timer.Create("DeleteHotloadedGMAsThroughAPI", 0.5, table.Count(HotloadedWSIDsQuery) * 3, function()
                -- This timer is bad! However, not sure how to tell the API to delete multiple paths. Wasted 1 hour trying to figure it out.
                local tbl = HotloadedWSIDsQuery[step]
                if not tbl then
                    print("tbl step not valid, returning")
                    PrintTable(HotloadedWSIDsQuery)
                    return
                end

                local cachepath = "/garrysmod/cache/srcds/" .. tbl["wsid"] .. ".gma"
                local steam_cachepath = "/steam_cache/content/4000/" .. tbl["wsid"]
                local steamapps_path = "/steamapps/workshop/content/4000/" .. tbl["wsid"]
                if i % 3 ~= 1 then
                    print("deleting " .. cachepath)
                    HTTPTable.parameters["paths[0]"] = cachepath
                elseif i % 3 == 2 then
                    print("deleting " .. steam_cachepath .. tbl["wsid"])
                    Clear_app_workshop_OfLingeringWSID(tbl["wsid"])
                    HTTPTable.parameters["paths[0]"] = steam_cachepath
                    step = step + 1
                elseif i % 3 == 0 then
                    print("deleting " .. steamapps_path .. tbl["wsid"])
                    sql.QueryTyped("DELETE FROM hotloaded_maps WHERE wsid = ?", tbl["wsid"])
                    HTTPTable.parameters["paths[0]"] = steam_cachepath
                end

                HTTP(HTTPTable)
                i = i + 1
            end)
        end
    end
end

local function GetStorageData()
    HTTP({
        method = "GET",
        url = "https://gamecp.physgun.com/api/client/servers/" .. SERVER_URL,
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/vnd.wisp.v1+json",
            ["Authorization"] = "Bearer " .. SERVER_TOKEN,
        },
        failed = function(reason) print("HTTP request failed", reason) end,
        success = function(code, body, headers)
            if code ~= 200 then
                print("Bad response: ", code, body)
            else
                local Tabled = util.JSONToTable(body)
                DiskLimit = Tabled["attributes"]["limits"]["disk"] * 1000000 -- this is in MB, so * 1000000 to be in bytes
                print("Got disk limit " .. DiskLimit)
                HTTP({
                    method = "GET",
                    url = "https://gamecp.physgun.com/api/client/servers/" .. SERVER_URL .. "/resources",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Accept"] = "application/vnd.wisp.v1+json",
                        ["Authorization"] = "Bearer " .. SERVER_TOKEN,
                    },
                    failed = function(reason) print("HTTP request failed", reason) end,
                    success = function(code_2, body_2, headers_2)
                        if code ~= 200 then
                            print("Bad response: ", code, body)
                        else
                            local tbled = util.JSONToTable(body_2)
                            DiskUsed = tbled["process"]["disk_used"]
                            print("Got disk used " .. DiskUsed)
                            DiskLeft = DiskLimit - DiskUsed
                            print("Disk left: " .. DiskLeft)
                        end
                    end
                })
            end
        end,
    })
end

GetStorageData()
Nominate.AddHook("InitPostEntity", "AddWorkshopForHotloadedMap", function()
    if (RealTime() < 30 and game.IsDedicated() == true) or (game.IsDedicated() == false and game.GetMapChangeCount() == 1) then -- if realtime is less than 30 the server recently started, therefore
        if WISPED == true then
            print("Getting storage data")
            GetStorageData()
        end

        print("deleting lingering hotloaded gmas")
        DeleteLingeringHotloadedGMAs()
        -- the table recording mounted gmas / hotloaded_maps doesn't matter, so
        -- delete that table so it doesn't grow too large. 
        -- the game.IsDedicated check is for listen servers. (since gmas never unmount, even when a listenserver gets shut down, to my knowledge).
        --[[
        if sql.TableExists("hotloaded_maps") then
            sql.QueryTyped("DELETE FROM hotloaded_maps")
            print("deleted hotloaded_maps table, server recently started")
        end
        --]]
        --
        -- if the server / game is recently up, we can safely remove all the gmas (since they are not mounted anymore). 
        -- we cannot remove a map's gma right after changeleveling to it unfortunately, because mounting a gma makes it open until the game is closed.
        DeleteDirectory("strippedhotloadgmas/")
        print("deleted strippedhotloadgmas/ folder, server recently started")
        return
    end

    if sql.TableExists("hotloaded_maps") then
        local CheckIfCurrentMapIsInSQLTable = sql.QueryTyped("SELECT * FROM hotloaded_maps WHERE mapname = ?", game.GetMap() .. ".bsp") -- move this to FindMapWorkshopID() later probably
        if CheckIfCurrentMapIsInSQLTable == false then
            error("CheckIfCurrentMapIsInSQLTable failed" .. (sql.LastError() or ""))
            return
        end

        local wsid = nil
        if CheckIfCurrentMapIsInSQLTable[1] then
            wsid = CheckIfCurrentMapIsInSQLTable[1]["wsid"]
            -- there should be an else statement here that errors if the map is not in engine.GetAddons(), but still exists.
            -- that would mean that the map has been hotloaded, but the sql table somehow wasnt updated, so then it should 
            -- error to tell the server about this. this is easily testable by destroying the listenserver and reconnecting, then loading to a hot loaded map. 
            -- maybe if this happens it should load to the server's default map (otherwise no one would be able to connect, which would kill server pop, so might as well switch to default map)
            -- do this later.
            print("Read this comment and do it later")
        end

        if not wsid then return end
        print("Current map is in hotloaded_maps table, " .. "resource.AddWorkshop(" .. wsid .. ")")
        resource.AddWorkshop(wsid)
        -- "Gamemodes that are workshop enabled and the current map are automatically added to this list, if they come from the servers' workshop collection - so there's no need to manually add them."
        -- from https://wiki.facepunch.com/gmod/resource.AddWorkshop
        -- the hotloaded maps, however, are not automatically added, so
        -- if you don't do this clients will get "map is missing" (and something about NET_MAXFILESIZEFRAGMENTS limit will print in the console) when loading into the server
    end
end)

--[[---------------
    Storage cleanup
-----------------]]
--[[---------------
    Chat commands
-----------------]]
--Pretty much just near copies of 
-- https://github.com/greyliterature/map_vote/blob/c5a8930302c9f53f0230409e845a9e8fc1f6aa3d/lua/mapvote/server/modules/rtv.lua#L127-L157
-- since those functions do the job pretty well already
local debugging = false -- remove this after testing
--
local NominationVotes = {} -- [mapname] = {ply1, ply2}
local function HasVotedForThisMap(ply, mapname)
    if table.Count(NominationVotes) == 0 then return end
    if not NominationVotes[mapname] then return end
    for playerobj, _ in pairs(NominationVotes[mapname]) do
        if ply == playerobj then return true end
        --if map == mapname then return true end
    end
    return false
end

local RTV = MapVote.RTV
Nominate.ChatCommands = {}
function Nominate.CanVote(ply, wsid, mapname, ugccallback)
    local conf = MapVote.GetConfig()
    if not wsid then
        ugccallback(false, "You must nominate a workshop id!")
        return
    end

    if Queued[wsid] then
        ugccallback(false, "That workshop id is already queued to download!")
        return
    end

    if debugging ~= true and RTV.GetPlayerCount() < conf.RTVPlayerCount then
        ugccallback(false, "You need more players before you can nominate a map!")
        return
    end

    if conf.EnableNomination == false then
        ugccallback(false, "Nomination is disabled!")
        return
    end

    if conf.NominateWait >= CurTime() then
        ugccallback(false, "You must wait " .. string.NiceTime(conf.NominateWait - CurTime()) .. " before voting to nominate a map!")
        return
    end

    if GetGlobalBool("In_Voting") then
        ugccallback(false, "There is currently a vote in progress!")
        return
    end

    if MapVote.state.isInProgress then
        ugccallback(false, "There is already a vote in progress")
        return
    end

    steamworks.FileInfo(wsid, function(data)
        if not data or data.error then
            ugccallback(false, "Workshop ID errored or is not a valid ID")
            return
        end

        if DiskLeft - data.size < conf.NominateByteThreshold then
            ugccallback(false, "That addon is " .. (conf.NominateByteThreshold - DiskLeft - data.size) .. " over the disk threshold. The server needs more disk space.")
            return
        end

        if data.size > conf.NominateMaxSizeBytes then
            ugccallback(false, "That addon is " .. data.size - conf.NominateMaxSizeBytes .. " bytes larger than the maxsize " .. conf.NominateMaxSizeBytes)
            return
        end

        Nominate.GetMapsFromAddon(wsid, function(PossibleMaps, firstmap)
            if table.Count(PossibleMaps) - 1 == 0 then
                ugccallback(false, "That addon does not have any maps!")
                return
            elseif table.Count(PossibleMaps) - 1 == 1 then
                mapname = firstmap
            end

            if debugging ~= true and HasVotedForThisMap(ply, mapname) == true then
                ugccallback(false, "Already voted for this map!")
                return
            end

            if mapname and not PossibleMaps[mapname] then
                ugccallback(false, "That addon does not have that map!\nAvailable maps:\n" .. table.concat(PossibleMaps["Arrayed"], "\n", 1, (#PossibleMaps["Arrayed"] > 5) or #PossibleMaps["Arrayed"]) .. ((table.Count(PossibleMaps) - 1 > 5 and "\n(more...)") or ""))
                return
            end

            ugccallback(true)
        end)
    end)
    --[[
    -- This isnt needed because "That addon does not have any maps!" return (should) captures this earlier
    steamworks.FileInfo(wsid, function(data)
        -- check if the wsid is valid
        print("TETSTTING")
        if data.error == -3 then
            return false, "must nominate a valid workshop ID"
        else
            return true
        end
    end)
    --]]
end

local MapCache = {}
function Nominate.GetMapsFromAddon(wsid, ugccallback)
    -- do downloadugc stuff here
    local firstmap = nil
    if MapCache[wsid] then
        print("WSID already searched, returning cache")
        for _, mapname in ipairs(MapCache[wsid]["Arrayed"]) do -- this is not ordered but that's probably ok.
            firstmap = mapname
            break
        end

        ugccallback(MapCache[wsid], firstmap)
    else
        steamworks.DownloadUGC_CACHED(wsid, function(filepath, _)
            MapCache[wsid] = {}
            MapCache[wsid]["Arrayed"] = {} -- for table.concat, this means that all table.counts of PossibleMaps will have to be subtracted one though.
            local files = GMA.Read(filepath, false, "GAME").Files
            for k, tbl in ipairs(files) do
                local OriginalPath = tbl.Name
                local DirectoryPath = string.match(OriginalPath, "^(.*)/[^/]+$")
                if string.lower(string.sub(DirectoryPath, 1, 4)) == "maps" and string.lower(string.sub(OriginalPath, #OriginalPath - 3, #OriginalPath)) == ".bsp" then
                    local mapname = string.sub(tbl.Name, 6, #tbl.Name - 4) -- "maps/mapname.bsp" becomes just "mapname"
                    if not firstmap then firstmap = mapname end
                    MapCache[wsid][mapname] = true
                    MapCache[wsid]["Arrayed"][#MapCache[wsid]["Arrayed"] + 1] = mapname
                    print("map added to list of maps in addon " .. wsid .. ": " .. mapname)
                else
                    continue
                end
            end

            ugccallback(MapCache[wsid], firstmap)
        end)
    end
end

function Nominate.GetThreshold()
    if debugging == true then return 0 end
    local conf = MapVote.GetConfig()
    local totalPlayers = RTV.GetPlayerCount() -- old RTV player count function works fine for this case
    local threshold = totalPlayers * conf.NominatePercentPlayersRequired
    return math.ceil(threshold)
end

local Nominations = {} -- tracking votes by wsid
-- should make this track maps too. addons add multiple maps at a time sometimes
function Nominate.AddVote(ply, wsid, mapname)
    Nominations[mapname] = ((Nominations[mapname] and Nominations[mapname]) or 0) + 1
    NominationVotes[mapname] = NominationVotes[mapname] or {}
    NominationVotes[mapname][ply] = true
    local threshold = Nominate.GetThreshold()
    DelayPrintMessage(HUD_PRINTTALK, ply:Nick() .. " has voted to add wsid " .. wsid .. ", " .. mapname .. " to be added to the RTV list. " .. "(" .. Nominations[mapname] .. "/" .. threshold .. ")")
end

function Nominate.MapShouldAdd(wsid, mapname)
    if MapVote.state.isInProgress then return end
    if debugging == true then return true end
    local conf = MapVote.GetConfig()
    local totalVotes = Nominations[mapname]
    local totalPlayers = RTV.GetPlayerCount()
    if totalPlayers < conf.RTVPlayerCount then return end
    if totalPlayers == 0 then return end
    return totalVotes >= Nominate.GetThreshold()
end

NominatedMaps = {}
function Nominate.AddToMapList(wsid, mapname)
    DelayPrintMessage(HUD_PRINTTALK, "Added " .. wsid .. ", " .. mapname .. " to rtv list.")
    NominatedMaps[#NominatedMaps + 1] = {wsid, mapname}
end

function Nominate.AddToMapListIfMapShouldAdd(wsid, mapname)
    if Nominate.MapShouldAdd(wsid, mapname) then
        Nominate.AddToMapList(wsid, mapname)
        return
    end
end

function Nominate.Map(ply, wsid, mapname)
    if not IsValid(ply) then return end
    Nominate.CanVote(ply, wsid, mapname, function(can, err)
        if can == false or can == nil then
            ply:DelayPrintMessage(HUD_PRINTTALK, err)
            return
        elseif can == true then
            Nominate.GetMapsFromAddon(wsid, function(PossibleMaps, firstmap)
                if table.Count(PossibleMaps) - 1 > 1 and not mapname then
                    ply:DelayPrintMessage(HUD_PRINTTALK, "That addon has multiple maps. Please send command again and specify which map you'd like to nominate (!nominate 12345 gm_mapname).\nAvailable maps:\n" .. table.concat(PossibleMaps["Arrayed"], "\n", 1, (#PossibleMaps["Arrayed"] > 5 and 5) or #PossibleMaps["Arrayed"]) .. ((table.Count(PossibleMaps) - 1 > 5 and "\n(more...)") or ""))
                    return
                elseif table.Count(PossibleMaps) - 1 == 1 then
                    mapname = firstmap
                end

                Nominate.AddVote(ply, wsid, mapname)
                Nominate.AddToMapListIfMapShouldAdd(wsid, mapname)
            end)
        end
    end)
end

Nominate.ChatCommands["!nominate"] = function(...) Nominate.Map(...) end
Nominate.AddHook("PlayerSay", "Nominate Chat Command", function(ply, text)
    text = string.lower(text)
    args = string.Explode(" ", text) -- !command -> 123, true, false <-
    cmd = args[1] -- !command
    table.remove(args, 1)
    local f = Nominate.ChatCommands[cmd]
    if f then
        f(ply, unpack(args))
        return
    end
end)

--[[---------------
    Detours
-----------------]]
Nominate._maps = nil
function Nominate.IsMapNominated(map) -- no .bsp
    for i = 1, #NominatedMaps do
        local tbl = NominatedMaps[i]
        local mapname = tbl[2]
        if mapname == map then
            print(map .. " was nominated")
            return true
        end
    end

    print(map .. " was not nominated")
    return false
end

function Nominate.WasMapHotloaded(map)
    map = map .. ".bsp"
    local CheckIfMapIsInSQLTable = sql.QueryTyped("SELECT * FROM hotloaded_maps WHERE mapname = ?", map)
    if CheckIfMapIsInSQLTable == false then
        ErrorNoHaltWithStack("CheckIfMapIsInSQLTable failed" .. (sql.LastError() or ""))
        return
    end

    if CheckIfMapIsInSQLTable[1] and CheckIfMapIsInSQLTable[1]["mapname"] == map then
        print(map .. " was hotloaded")
        return true
    end

    print(map .. " was not hotloaded")
    return false
end

Nominate.AddHook("MapVote_SelectMaps", "PutNominatedMapsInTable", function()
    --if #NominatedMaps == 0 then return end -- if this returns early then the bug with all of the hotloaded / newly mounted maps being part of the rtv list happens
    local mapsInVote = {}
    local maps = MapVote.getMapList()
    local MapCount = 1
    for _, map in RandomPairs(maps) do
        if Nominate.IsMapNominated(map) then
            print(map .. " is nominated, not adding to original maps table")
            continue
        end

        if Nominate.WasMapHotloaded(map) then
            print(map .. " was hotloaded, not adding to original maps table")
            continue
        end

        if MapVote.isMapAllowed(map) then
            table.insert(mapsInVote, map)
            MapCount = MapCount + 1
            if MapCount > MapVote.config.MapLimit - #NominatedMaps then
                print("stopped adding non nominated maps past " .. MapCount)
                break
            end
        end
    end

    for i = 1, #NominatedMaps do
        local tbl = NominatedMaps[i]
        local mapname = tbl[2]
        print("adding nominated map " .. mapname .. " to votemap table")
        table.insert(mapsInVote, mapname)
    end
    return mapsInVote
end)

Nominate.AddHook("MapVote_ChangeMap", "DelayMapChangeIfHotloaded", function(map)
    for _, tbl in ipairs(NominatedMaps) do
        local mapname = tbl[2]
        if mapname == map then --
            return false
        end
    end
end)

Nominate.AddHook("MapVote_VoteFinished", "ChangeMapOnMount", function(resultstable)
    --
    if #NominatedMaps == 0 then return end
    local winningmap = resultstable.state.currentMaps[resultstable.winner]
    local SecondWinningNonNominatedMap = resultstable.state.currentMaps[resultstable.winner - 1]
    for i = resultstable.winner, 1, -1 do
        local mapname = resultstable.state.currentMaps[i]
        if Nominate.IsMapNominated(mapname) then continue end
        SecondWinningNonNominatedMap = mapname
    end

    for _, tbl in ipairs(NominatedMaps) do
        local wsid = tbl[1]
        local mapname = tbl[2]
        if mapname == winningmap then
            HotloadMap(wsid, function(succ)
                if succ == true then
                    PrintMessage(HUD_PRINTTALK, "Attempting to change level to hotloaded map " .. wsid .. ", " .. mapname)
                    RunConsoleCommand("changelevel", mapname)
                else
                    PrintMessage(HUD_PRINTTALK, "Failed to mount GMA of " .. wsid .. ". changing map to second highest non nominated winner.")
                    RunConsoleCommand("changelevel", SecondWinningNonNominatedMap)
                end
            end)

            break
        end
    end
end)
