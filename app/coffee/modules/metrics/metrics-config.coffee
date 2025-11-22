###
# CREADOR POR: POL ALCOVERRO
# Descripción: Controlador para el panel de configuración de métricas (LIVE).
# Permite clasificar métricas como de Proyecto o de Equipo y configurar el proveedor.
###

module = angular.module("taigaMetrics")

class MetricsConfigController
    @.$inject = [
        "$scope",
        "$routeParams",
        "$tgHttp",
        "$tgUrls",
        "tgMetricsConfiguration",
        "tgProjectService",
        "$translate",
        "tgAppMetaService"
    ]

    constructor: (@scope, @params, @http, @urls, @metricsConfig, @projectService, @translate, @appMetaService) ->
        @scope.projectSlug = @params.pslug
        @scope.loading = true
        @scope.metrics = []
        @scope.config = {
            provider: @metricsConfig.provider
            classification: {} # metricId -> 'project' | 'team' | 'hidden'
        }
        
        # Load saved config from localStorage if available
        @.loadLocalConfig()

        @.loadProject()

    loadLocalConfig: ->
        try
            saved = localStorage.getItem("taigaMetricsConfig_#{@scope.projectSlug}")
            if saved
                parsed = JSON.parse(saved)
                @scope.config = _.merge(@scope.config, parsed)
        catch e
            console.error "Error loading local config", e

    loadProject: ->
        # Project is preloaded by the route resolver (app.coffee)
        if @projectService.project
            @scope.project = @projectService.project.toJS()
            @.initProjectData()
        else
            # Fallback if for some reason it wasn't loaded
            @projectService.setProjectBySlug(@scope.projectSlug).then =>
                @scope.project = @projectService.project.toJS()
                @.initProjectData()

    initProjectData: ->
        title = "Metrics Configuration - #{@scope.project.name}"
        @appMetaService.setAll(title, "Configure metrics classification")
        
        # Initialize external ID from config or default
        resolvedId = @metricsConfig.resolveExternalProjectId(@scope.projectSlug)
        @scope.externalProjectId = resolvedId or @scope.projectSlug
        
        @.checkAuthAndLoad()

    checkAuthAndLoad: ->
        @scope.loading = true
        @scope.authRequired = false
        
        url = @urls.resolve("metrics-status")
        params = { source: @scope.config.provider }

        @http.get(url, params, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}
                console.log "Metrics Config: Auth status", data
                if data.authenticated
                    @.loadMetrics()
                else
                    @scope.loading = false
                    @scope.authRequired = true
            .catch (error) =>
                console.error "Metrics Config: Auth check failed", error
                @scope.loading = false
                @scope.error = "Error checking authentication status."

    loadMetrics: ->
        @scope.loading = true
        @scope.error = null
        
        # Use the ID from the input field
        externalId = @scope.externalProjectId
        
        params =
            project: @scope.projectSlug
            source: @scope.config.provider

        if externalId
            params.external = externalId

        console.log "Metrics Config: Loading metrics with params", params
        url = @urls.resolve("metrics")
        
        @http.get(url, params, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}
                console.log "Metrics Config: Loaded data", data
                rawMetrics = data.metrics or []
                @.processMetricsList(rawMetrics)
                @scope.loading = false
            .catch (error) =>
                console.error "Metrics Config: Error loading metrics", error
                @scope.loading = false
                @scope.error = "Error loading metrics. Server returned: " + (error.data?.error or error.statusText)

    processMetricsList: (rawMetrics) ->
        uniqueMetrics = {}
        
        for metric in rawMetrics
            continue unless metric and metric.id
            id = metric.id
            
            unless uniqueMetrics[id]
                uniqueMetrics[id] = {
                    id: id
                    name: metric.name or id
                    description: metric.description
                    # Determine current default classification
                    defaultType: if @.isDefaultTeamMetric(id) then 'team' else 'project'
                }

        @scope.metrics = _.values(uniqueMetrics).sort (a, b) ->
            a.id.localeCompare(b.id)
        
        console.log "Metrics Config: Processed metrics", @scope.metrics.length

        # Initialize config for new metrics
        for metric in @scope.metrics
            unless @scope.config.classification[metric.id]
                @scope.config.classification[metric.id] = metric.defaultType

    isDefaultTeamMetric: (metricId) ->
        # Logic duplicated from main.coffee for default determination
        lowerId = metricId.toLowerCase()
        prefixes = [
            "assignedtasks_"
            "closedtasks_"
            "completedtasks_"
            "commits_"
            "modifiedlines_"
            "completedus_"
            "totalus_"
            "tasksratio_"
        ]
        return prefixes.some (prefix) -> lowerId.indexOf(prefix) is 0

    saveConfig: ->
        # Save to localStorage for "LIVE" effect on this browser
        key = "taigaMetricsConfig_#{@scope.projectSlug}"
        localStorage.setItem(key, JSON.stringify(@scope.config))
        alert("Configuration saved to LocalStorage! Refresh the metrics page to see changes.")

    exportConfig: ->
        # Generate a JSON file for the user to download
        dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(@scope.config, null, 2))
        downloadAnchorNode = document.createElement('a')
        downloadAnchorNode.setAttribute("href", dataStr)
        downloadAnchorNode.setAttribute("download", "metrics_config_#{@scope.projectSlug}.json")
        document.body.appendChild(downloadAnchorNode)
        downloadAnchorNode.click()
        downloadAnchorNode.remove()

    toggleProvider: ->
        @scope.config.provider = if @scope.config.provider is 'internal' then 'external' else 'internal'
        @.checkAuthAndLoad() # Re-check auth and load metrics from new provider

module.controller("MetricsConfigController", MetricsConfigController)
