require "schemavalidator"
local SV = SchemaValidator

local schema = SV.Object {
    MapLimit = SV.Int { min = 2 },
    TimeLimit = SV.Int { min = 1 },
    AllowCurrentMap = SV.Bool(),
    RTVPercentPlayersRequired = SV.Number { min = 0, max = 1 },
    RTVPercentWhenOverpopulated = SV.Number { min = 0, max = 1 },
    RTVWait = SV.Number(),
    VoteMultipliers = SV.Map( SV.String(), SV.Int { min = 0, max = 99 } ):Optional(),
    SortMaps = SV.Bool(),
    UseGamemodeMapPrefixes = SV.Bool():Optional(),
    MapPatterns = SV.List( SV.String() ):Optional(),
    EnableCooldown = SV.Bool(),
    MapsBeforeRevote = SV.Int { min = 1 },
    RTVPlayerCount = SV.Int { min = 1 },
    ExcludedMaps = SV.Map( SV.String(), SV.Bool() ),
    IncludedMaps = SV.Map( SV.String(), SV.Bool() ),
    MapConfig = SV.Map( SV.String(), SV.Object( {
        MinPlayers = SV.Int { min = 0 }:Optional(),
        MaxPlayers = SV.Int { min = 0 }:Optional(),
        CooldownMinutes = SV.Int { min = 0 }:Optional(),
    } ) ):Optional(),
    PlyRTVCooldownSeconds = SV.Int { min = 1 },
    MapIconURLs = SV.Map( SV.String(), SV.String() ):Optional(),
    EnableNomination = SV.Bool(),
    NominateWait = SV.Number(),
    NominatePercentPlayersRequired = SV.Number { min = 0, max = 1 },
    NominateMaxSizeBytes = SV.Int { min = 1 },
    NominateByteThreshold = SV.Int { min = 5000000 }
}

local default = {
    MapLimit = 24,
    TimeLimit = 28,
    RTVWait = 60,
    VoteMultipliers = {},
    AllowCurrentMap = false,
    EnableCooldown = true,
    MapsBeforeRevote = 3,
    RTVPlayerCount = 3,
    UseGamemodeMapPrefixes = false,
    MapPatterns = { "*" },
    IncludedMaps = {},
    ExcludedMaps = {
        ["test_hardware"] = true,
        ["test_speakers"] = true,
    },
    RTVPercentPlayersRequired = 0.66,
    RTVPercentWhenOverpopulated = 0,
    SortMaps = false,
    PlyRTVCooldownSeconds = 120,
    MapIconURLs = {},
    MapConfig = {},
    EnableNomination = false,
    NominateWait = 60,
    NominatePercentPlayersRequired = 0.66,
    NominateMaxSizeBytes = 500000000,
    NominateByteThreshold = 20000000000,
}

MapVote.configSchema = schema
MapVote.configDefault = default
