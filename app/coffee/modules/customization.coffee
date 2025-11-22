###
# CREADOR POR: POL ALCOVERRO
# Descripción: Hooks de personalización para el módulo de métricas mediante window.taigaCustomizationHooks.metrics.
###

module = angular.module("taigaCustomization", [])

module.factory "tgMetricsCustomization", ["$log", ($log) ->
    ###
    # Created by: Pol Alcoverro
    # Description: Builds the active metrics customization hooks merging defaults with optional overrides.
    ###

    defaultHooks =
        transformMetricsPayload: (ctx) -> ctx?.data
        transformMetricsView: (ctx) -> ctx?.viewData
        transformProjectMetrics: (ctx) -> ctx?.metrics
        transformHistoricalPayload: (ctx) -> ctx?.data
        transformTeamHistoricalCharts: (ctx) -> ctx?.charts
        transformProjectHistoricalCharts: (ctx) -> ctx?.charts
        resolveGaugeValue: (ctx) -> ctx?.defaultValue

    resolveOverrides = ->
        globalHooks = window.taigaCustomizationHooks?.metrics or window.taigaMetricsCustomization
        return globalHooks or {}

    activeHooks = _.merge({}, defaultHooks, resolveOverrides())

    service =
        ###
        # Created by: Pol Alcoverro
        # Description: Returns the current metrics customization hooks.
        ###
        getMetricsHooks: ->
            return angular.copy(activeHooks)

        ###
        # Created by: Pol Alcoverro
        # Description: Allows runtime overrides to be applied programmatically.
        ###
        applyOverrides: (newOverrides) ->
            overrides = newOverrides or {}
            activeHooks = _.merge({}, defaultHooks, overrides)
            $log.debug("tgMetricsCustomization overrides applied")

    return service
]
