###
# CREADOR POR: POL ALCOVERRO
# Descripción: Servicio central de configuración de métricas con posibilidad de overrides vía window.taigaMetricsConfig.
###

module = angular.module("taigaMetrics")

module.factory "tgMetricsConfiguration", ["$log", ($log) ->
    ###
    # Created by: Pol Alcoverro
    # Description: Builds the default configuration object and merges external overrides.
    ###
    defaultConfig =
        provider: "internal"
        externalProjectIds: [
            "AMEP11Beats",
            "AMEP11ChopChop",
            "AMEP11UniMatch",
            "AMEP11Unimatch",
            "AMEP12Academy4All",
            "AMEP21Cano3",
            "AMEP21Krunkillos",
            "AMEP21Sportifiers",
            "AMEP21SportifyCoach",
            "AMEP22GoRace",
            "AMEP22TicketMonster",
            "AMEP22TicketMonsterTM",
            "LD_TEST_Project",
            "Test",
            "it12b",
            "it12c",
            "it12d"
        ]
        projectMetricsOrder: [
            "acceptance_criteria_check",
            "closed_tasks_with_ae",
            "commits_anonymous",
            "commits_sd",
            "commits_taskreference",
            "deviation_effort_estimation_simple",
            "learn_hours",
            "pattern_check",
            "tasks_sd",
            "tasks_with_ee",
            "unassignedtasks"
        ]
        projectHistoricalMetricsOrder: [
            "acceptance_criteria_check",
            "deviation_effort_estimation_simple",
            "learn_hours",
            "tasks_sd",
            "tasks_with_ee",
            "unassignedtasks"
        ]

    externalOverrides = window.taigaMetricsConfig or {}
    configuration = _.merge({}, defaultConfig, externalOverrides)

    ###
    # Created by: Pol Alcoverro
    # Description: Produces a normalized identifier used as key for project lookups.
    ###
    normalizeId = (value) ->
        return "" unless value
        return value.replace(/[^a-z0-9]/ig, "").toLowerCase()

    ###
    # Created by: Pol Alcoverro
    # Description: Generates a map from normalized ids to their canonical external ids.
    ###
    buildProjectIdMap = (ids) ->
        map = {}
        _.forEach ids, (externalId) ->
            normalized = normalizeId(externalId)
            map[normalized] = externalId unless map[normalized]?
        return map

    projectIdMap = buildProjectIdMap(configuration.externalProjectIds)

    ###
    # Created by: Pol Alcoverro
    # Description: Resolves the external project id consuming overrides when present.
    ###
    resolveExternalProjectId = (slug) ->
        return "" unless slug
        normalized = normalizeId(slug)
        if projectIdMap[normalized]?
            return projectIdMap[normalized]
        return slug

    resolveProvider = ->
        provider = configuration.provider or "external"
        provider = provider.toString().trim().toLowerCase()
        if provider not in ["internal", "external"]
            provider = "external"
        return provider

    configuration.normalizeId = normalizeId
    configuration.externalProjectIdMap = projectIdMap
    configuration.resolveExternalProjectId = resolveExternalProjectId
    configuration.resolveProvider = resolveProvider

    $log.debug("tgMetricsConfiguration initialized")

    return configuration
]
