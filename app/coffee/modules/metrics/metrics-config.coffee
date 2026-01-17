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
        "$q",
        "tgMetricsConfiguration",
        "tgProjectService",
        "$tgResources",
        "$translate",
        "tgAppMetaService"
    ]

    constructor: (@scope, @params, @http, @urls, @$q, @metricsConfig, @projectService, @rs, @translate, @appMetaService) ->
        @scope.projectSlug = @params.pslug
        @scope.loading = true
        @scope.metrics = []
        @scope.config = {
            provider: @metricsConfig.provider
            classification: {} # metricId -> 'project' | 'team' | 'hidden'
        }
        @scope.configLoading = false
        @scope.savingConfig = false
        @scope.configError = null

        @.loadProject()

    loadServerConfig: ->
        unless @scope.projectSlug
            return @$q.when(null)

        @scope.configLoading = true
        @scope.configError = null

        url = @urls.resolve("metrics-config")
        params = {project: @scope.projectSlug}

        return @http.get(url, params, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}
                if data.provider
                    @scope.config.provider = data.provider

                if angular.isObject(data.classification)
                    @scope.config.classification = data.classification
                else
                    @scope.config.classification = {}

                if angular.isString(data.external_project_id) and data.external_project_id.length
                    @scope.externalProjectId = data.external_project_id
            .catch (error) =>
                console.error "Metrics Config: Error loading server configuration", error
                @scope.configError = "Unable to load the saved metrics configuration for this project."
                return @$q.reject(error)
            .finally =>
                @scope.configLoading = false

    resetMetricsState: ->
        @scope.metrics = []
        @scope.error = null
        @scope.authRequired = false
        @scope.loading = false

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
        
        @.loadServerConfig().finally =>
            @.checkAuthAndLoad()
            @.loadSprints()

    checkAuthAndLoad: ->
        @scope.loading = true
        @scope.metrics = []
        @scope.error = null
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
        @scope.metrics = []
        
        # Use the ID from the input field
        externalId = @scope.externalProjectId
        
        params =
            project: @scope.projectSlug
            source: @scope.config.provider

        if @scope.config.provider is 'internal'
            params.refresh = true

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
                @scope.metrics = []
                @scope.error = "Error loading metrics. Server returned: " + (error.data?.error or error.statusText)

    processMetricsList: (rawMetrics) ->
        unless angular.isArray(rawMetrics)
            @scope.metrics = []
            return []

        normalizeId = (value) ->
            return null unless value?
            value.toString().trim()

        guessDefaultType = (metric) =>
            idsToCheck = []
            idsToCheck.push(normalizeId(metric.id)) if metric?.id?
            idsToCheck.push(normalizeId(metric.externalId)) if metric?.externalId?

            for candidate in idsToCheck when candidate?
                lower = candidate.toLowerCase()
                return 'team' if @.isDefaultTeamMetric(lower)
                return 'team' if @.isUserMetricId(lower)
            'project'

        uniqueMetrics = {}

        for metric in rawMetrics when metric?
            id = normalizeId(metric.id) or normalizeId(metric.externalId)
            continue unless id

            uniqueMetrics[id] =
                id: id
                name: metric?.name or id
                description: metric?.description
                defaultType: guessDefaultType(metric)

        @scope.metrics = _.values(uniqueMetrics).sort (a, b) ->
            a.name.toString().localeCompare(b.name.toString())

        console.log "Metrics Config: Processed metrics (full list)", @scope.metrics.length

        # Initialize config for new metrics
        for metric in @scope.metrics
            unless @scope.config.classification[metric.id]
                @scope.config.classification[metric.id] = metric.defaultType

    isDefaultTeamMetric: (metricId) ->
        # Use centralized configuration to determine if it's a team metric
        return false unless metricId

        # Check if it's in the team metrics order list
        teamOrder = @metricsConfig.teamMetricsOrder or []
        for teamMetric in teamOrder
            lowerTeam = teamMetric.toLowerCase()
            lowerId = metricId.toLowerCase()
            if lowerId is lowerTeam or lowerId.indexOf("#{lowerTeam}_") is 0 or lowerId.indexOf("#{lowerTeam}-") is 0
                return true
                
        return false

    isUserMetricId: (metricId) ->
        return false unless metricId?
        lowerId = metricId.toString().toLowerCase()
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
        prefixes.some (prefix) -> lowerId.indexOf(prefix) is 0

    saveConfig: ->
        payload = {
            project: @scope.projectSlug
            provider: @scope.config.provider
            classification: @scope.config.classification
            externalProjectId: @scope.externalProjectId
        }

        @scope.savingConfig = true
        @scope.error = null

        url = @urls.resolve("metrics-config")
        @http.patch(url, payload, null, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}
                if angular.isObject(data.classification)
                    @scope.config.classification = data.classification
                if data.external_project_id? and data.external_project_id isnt undefined
                    @scope.externalProjectId = data.external_project_id
                alert("Configuration saved! All members will now share this metrics setup.")
            .catch (error) =>
                console.error "Metrics Config: Error saving configuration", error
                @scope.error = "Error saving metrics configuration."
            .finally =>
                @scope.savingConfig = false

    exportConfig: ->
        exportData = angular.copy(@scope.config) or {}
        exportData.externalProjectId = @scope.externalProjectId
        dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(exportData, null, 2))
        downloadAnchorNode = document.createElement('a')
        downloadAnchorNode.setAttribute("href", dataStr)
        downloadAnchorNode.setAttribute("download", "metrics_config_#{@scope.projectSlug}.json")
        document.body.appendChild(downloadAnchorNode)
        downloadAnchorNode.click()
        downloadAnchorNode.remove()

    toggleProvider: ->
        @scope.config.provider = if @scope.config.provider is 'internal' then 'external' else 'internal'
        @.resetMetricsState()
        @.checkAuthAndLoad() # Re-check auth and load metrics from new provider

    loadSprints: ->
        params = {closed: false}
        @rs.sprints.list(@scope.projectId, params).then (result) =>
            sprints = result.milestones
            @scope.sprints = sprints
            @scope.currentSprint = @.findCurrentSprint(sprints)

    findCurrentSprint: (sprints) ->
        return null unless sprints and sprints.length
        currentDate = new Date().getTime()

        return _.find sprints, (sprint) ->
            start = moment(sprint.estimated_start, 'YYYY-MM-DD').format('x')
            end = moment(sprint.estimated_finish, 'YYYY-MM-DD').format('x')
            return currentDate >= start && currentDate <= end

module.controller("MetricsConfigController", MetricsConfigController)
