###
# CREADOR POR: POL ALCOVERRO
# Descripción: Controlador y vista lógica del dashboard de métricas integradas con Learning Dashboard.
###

###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
# Pol Alcoverro added - Metrics module
#
# Metrics integration updated to mirror the Learning Dashboard extension
# including authentication flow and extended data retrieval.
###

taiga = @.taiga
mixOf = @.taiga.mixOf

module = angular.module("taigaMetrics")

#############################################################################
## Metrics Controller
## Pol Alcoverro added - Controller for displaying project metrics
#############################################################################

class MetricsController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope",
        "$rootScope",
        "$tgRepo",
        "$tgResources",
        "$routeParams",
        "$q",
        "$location",
        "$tgNavUrls",
        "tgAppMetaService",
        "$tgAuth",
        "$translate",
        "tgProjectService",
        "tgErrorHandlingService",
        "$tgHttp",
        "$tgUrls",
        "$timeout",
        "tgMetricsConfiguration",
        "tgMetricsCustomization"
    ]

    constructor: (@scope, @rootscope, @repo, @rs, @params, @q, @location, @navUrls, @appMetaService, @auth,
                  @translate, @projectService, @errorHandlingService, @http, @urls, @$timeout, metricsConfiguration,
                  metricsCustomization) ->
        @scope.sectionName = "METRICS.SECTION_NAME"
        @scope.projectSlug = @params.pslug
        @metricsConfig = metricsConfiguration
        @metricsHooks = metricsCustomization.getMetricsHooks()

        fallbackHooks =
            transformMetricsPayload: (ctx) -> ctx?.data
            transformMetricsView: (ctx) -> ctx?.viewData
            transformProjectMetrics: (ctx) -> ctx?.metrics
            transformHistoricalPayload: (ctx) -> ctx?.data
            transformTeamHistoricalCharts: (ctx) -> ctx?.charts
            transformProjectHistoricalCharts: (ctx) -> ctx?.charts
            resolveGaugeValue: (ctx) -> ctx?.defaultValue

        @metricsHooks = _.defaults(@metricsHooks or {}, fallbackHooks)

        providerResolver = @metricsConfig?.resolveProvider
        if angular.isFunction(providerResolver)
            @metricsProvider = providerResolver.call(@metricsConfig)
        else
            @metricsProvider = @metricsConfig?.provider or "external"

        if angular.isString(@metricsProvider)
            @metricsProvider = @metricsProvider.toLowerCase()
        else
            @metricsProvider = "external"

        @legacyLocalConfig = @.loadLocalConfig()
        @localConfig = null
        if @legacyLocalConfig?.provider
            @metricsProvider = @legacyLocalConfig.provider

        @scope.metricsAuth =
            authenticated: true
            username: null
            externalProjectId: null
            loading: false
            checking: false
            error: null
            form:
                username: ""

        @scope.metricsView =
            loading: true
            error: null
            isNewProject: false
            data: null
            errors: {}
            activeTab: if @location.path().indexOf('/metrics/project') != -1 then 'project' else 'team'
            showHistorical: false
            showTesting: false
            historicalExpanded: {}  # Control de acordeón para secciones históricas
            teamSubTab: "overview"
            projectSubTab: "overview"
            teamOverview: @.buildTeamOverviewDefaultState()
            teamHistoricalFilters:
                metric: "all"
                user: "all"
                dateFrom: null
                dateTo: null
                preset: null
                sprint: null
            teamHistoricalMetricOptions: [
                {id: "all", label: "METRICS.TEAM_HISTORICAL_METRIC_ALL"}
                {id: "tasks", label: "METRICS.TEAM_HISTORICAL_METRIC_TASKS"}
                {id: "closed_tasks", label: "METRICS.TEAM_HISTORICAL_METRIC_CLOSED_TASKS"}
                {id: "modified_lines", label: "METRICS.TEAM_HISTORICAL_METRIC_MODIFIED_LINES"}
                {id: "commits", label: "METRICS.TEAM_HISTORICAL_METRIC_COMMITS"}
                {id: "story_points", label: "METRICS.TEAM_HISTORICAL_METRIC_STORY_POINTS"}
                {id: "stories_closed", label: "METRICS.TEAM_HISTORICAL_METRIC_STORIES_CLOSED"}
            ]
            teamHistoricalUserOptions: [
                {id: "all", label: "METRICS.TEAM_HISTORICAL_ALL_USERS", translate: true}
            ]
            teamHistoricalCharts: []
            teamHistoricalSource: null
            projectHistoricalCharts: []
            projectHistoricalFilters:
                metric: "all"
                dateFrom: null
                dateTo: null
                preset: null
                sprint: null
            projectHistoricalMetricOptions: [
                {id: "all", label: "METRICS.TEAM_HISTORICAL_METRIC_ALL"}
            ]
            # Sprint options
            sprintOptions: [
                {id: null, name: "METRICS.SPRINT_GLOBAL", translate: true}
            ]
            # Date presets for quick filtering
            datePresetOptions: [
                {id: null, label: "METRICS.DATE_PRESET_CUSTOM", translate: true}
                {id: "last_7_days", label: "METRICS.DATE_PRESET_LAST_7_DAYS", translate: true}
                {id: "last_14_days", label: "METRICS.DATE_PRESET_LAST_14_DAYS", translate: true}
                {id: "last_30_days", label: "METRICS.DATE_PRESET_LAST_30_DAYS", translate: true}
                {id: "last_90_days", label: "METRICS.DATE_PRESET_LAST_90_DAYS", translate: true}
                {id: "current_month", label: "METRICS.DATE_PRESET_CURRENT_MONTH", translate: true}
                {id: "current_semester", label: "METRICS.DATE_PRESET_CURRENT_SEMESTER", translate: true}
                {id: "last_semester", label: "METRICS.DATE_PRESET_LAST_SEMESTER", translate: true}
                {id: "last_year", label: "METRICS.DATE_PRESET_LAST_YEAR", translate: true}
                {id: "all_time", label: "METRICS.DATE_PRESET_ALL_TIME", translate: true}
            ]

        @userColorPalette = @.buildUserColorPalette()
        @metricsCategoryPalettes = {}
        @qualityFactorNamesMap = {}
        @resetUserColorAssignments()

        @scope.availableTabs = [
            {id: "team", label: "METRICS.TABS.TEAM"}
            {id: "project", label: "METRICS.TABS.PROJECT"}
        ]

        @scope.setActiveTab = (tabId) =>
            @scope.metricsView.activeTab = tabId
            projectSlug = @scope.project.slug
            if tabId == 'project'
                @location.path("/project/#{projectSlug}/metrics/project")
            else
                @location.path("/project/#{projectSlug}/metrics/team")

        @scope.setTeamSubTab = (tabId) =>
            return unless tabId
            @scope.metricsView.teamSubTab = tabId
            if tabId is "historical"
                @.applyTeamHistoricalFilters()

        @scope.setProjectSubTab = (tabId) =>
            return unless tabId
            @scope.metricsView.projectSubTab = tabId
            if tabId is "historical"
                @.updateProjectHistoricalCharts(@scope.metricsView.data?.historicalMetrics)

        @scope.toggleHistorical = =>
            @scope.metricsView.showHistorical = !@scope.metricsView.showHistorical

        @scope.toggleHistoricalSection = (sectionName) =>
            if !@scope.metricsView.historicalExpanded[sectionName]?
                @scope.metricsView.historicalExpanded[sectionName] = true
            else
                @scope.metricsView.historicalExpanded[sectionName] = !@scope.metricsView.historicalExpanded[sectionName]

        @scope.loginMetrics = =>
            @.loginMetrics()

        @scope.logoutMetrics = =>
            @.logoutMetrics()

        @scope.reloadMetrics = =>
            @.loadMetrics(true)
        
        @scope.showTestingView = =>
            @scope.metricsView.showTesting = true
            setTimeout(@.drawTestingCharts, 100)
        
        @scope.hideTestingView = =>
            @scope.metricsView.showTesting = false

        @scope.clearTeamHistoricalDates = =>
            filters = @scope.metricsView.teamHistoricalFilters
            return unless filters?
            filters.dateFrom = null
            filters.dateTo = null
            filters.preset = null

        @scope.clearProjectHistoricalDates = =>
            filters = @scope.metricsView.projectHistoricalFilters
            return unless filters?
            filters.dateFrom = null
            filters.dateTo = null
            filters.preset = null

        # Apply date preset and calculate actual dates
        @scope.applyTeamDatePreset = (presetId) =>
            @.applyDatePreset(@scope.metricsView.teamHistoricalFilters, presetId)
        
        @scope.applyProjectDatePreset = (presetId) =>
            @.applyDatePreset(@scope.metricsView.projectHistoricalFilters, presetId)

        @scope.applySprintFilter = (targetFilters) =>
            @.applySprintFilter(targetFilters)

        @scope.toggleTeamOverviewUser = (username) =>
            @.toggleTeamOverviewUser(username)

        @scope.resetTeamOverviewUsers = =>
            @.resetTeamOverviewUsers()

        @scope.$watch "metricsView.teamHistoricalFilters", (newFilters, oldFilters) =>
            return unless newFilters?
            return if newFilters is oldFilters
            @.applyTeamHistoricalFilters()
        , true

        @scope.$watch "metricsView.projectHistoricalFilters", (newFilters, oldFilters) =>
            return unless newFilters?
            return if newFilters is oldFilters
            @.applyProjectHistoricalFilters()
        , true

        @scope.$watch "metricsView.data.historicalMetrics", (historicalMetrics) =>
            return unless historicalMetrics?
            @.updateTeamHistoricalSource(historicalMetrics)
        
        promise = @.loadInitialData()

        promise.then =>
            title = @translate.instant("METRICS.PAGE_TITLE", {projectName: @scope.project.name})
            description = @translate.instant("METRICS.PAGE_DESCRIPTION", {
                projectName: @scope.project.name,
                projectDescription: @scope.project.description
            })
            @appMetaService.setAll(title, description)
            @.bootstrapMetricsAccess()
            @.loadMilestones()

        promise.then null, @.onInitialDataError.bind(@)

    loadLocalConfig: ->
        try
            slug = @params.pslug
            saved = localStorage.getItem("taigaMetricsConfig_#{slug}")
            return JSON.parse(saved) if saved
        catch e
            console.error "Error loading local config", e
        return null

    fetchProjectConfig: ->
        slug = @params.pslug
        return @q.when(@legacyLocalConfig) unless slug

        url = @urls.resolve("metrics-config")
        params = {project: slug}

        return @http.get(url, params, {withCredentials: true})
            .then (response) =>
                config = @.normalizeConfigPayload(response?.data)
                if config
                    console.log "Metrics: Loaded configuration from SERVER for project #{slug}", config
                    @localConfig = config
                    if config.provider
                        @metricsProvider = config.provider
                    if config.externalProjectId
                        @scope.metricsAuth.externalProjectId = config.externalProjectId
                else
                    console.log "Metrics: No configuration from server, using defaults/legacy"
                    @localConfig = null
                return @localConfig
            .catch (error) =>
                console.error "Metrics: unable to load persisted config", error
                if @legacyLocalConfig
                    console.log "Metrics: Using LEGACY local config", @legacyLocalConfig
                    @localConfig = @legacyLocalConfig
                    if @localConfig.provider
                        @metricsProvider = @localConfig.provider
                    if @localConfig.externalProjectId and !@scope.metricsAuth.externalProjectId
                        @scope.metricsAuth.externalProjectId = @localConfig.externalProjectId
                else
                    console.log "Metrics: Using DEFAULT hardcoded config"
                return @localConfig

    normalizeConfigPayload: (data) ->
        return null unless data and angular.isObject(data)

        normalized =
            provider: null
            classification: data.classification or {}
            externalProjectId: data.external_project_id or data.externalProjectId or null
            projectMetricsOrder: data.project_metrics_order or data.projectMetricsOrder or []
            teamMetricsOrder: data.team_metrics_order or data.teamMetricsOrder or []

        providerValue = data.provider or data.metrics_provider
        if angular.isString(providerValue)
            normalized.provider = providerValue.toLowerCase()

        defaultProjectOrder = if angular.isArray(@metricsConfig?.projectMetricsOrder) then @metricsConfig.projectMetricsOrder.slice() else []
        defaultTeamOrder = if angular.isArray(@metricsConfig?.teamMetricsOrder) then @metricsConfig.teamMetricsOrder.slice() else []

        if angular.isString(normalized.externalProjectId)
            normalized.externalProjectId = normalized.externalProjectId.trim()
        else
            normalized.externalProjectId = null

        if !angular.isObject(normalized.classification)
            normalized.classification = {}

        if !angular.isArray(normalized.projectMetricsOrder)
            normalized.projectMetricsOrder = []
        if normalized.projectMetricsOrder.length is 0 and defaultProjectOrder.length > 0
            normalized.projectMetricsOrder = defaultProjectOrder

        if !angular.isArray(normalized.teamMetricsOrder)
            normalized.teamMetricsOrder = []
        if normalized.teamMetricsOrder.length is 0 and defaultTeamOrder.length > 0
            normalized.teamMetricsOrder = defaultTeamOrder

        return normalized

    resolveLocalClassification: (metricId) ->
        return null unless metricId?
        return null unless @localConfig?.classification
        classification = @localConfig.classification[metricId]
        if classification?
            return classification
        lower = metricId.toString().toLowerCase()
        return @localConfig.classification[lower] if lower isnt metricId and @localConfig.classification[lower]?
        return null

    resolveMetricClassificationValue: (metric) ->
        return null unless metric?
        classification = null

        # Check scope from API to determine classification
        # scope: "team" -> Project Metrics (aggregate)
        # scope: "individual" -> Team Metrics (per user)
        if metric.scope
            if metric.scope == 'team'
                classification = 'project'
            else if metric.scope == 'individual'
                classification = 'team'

        if !classification and metric.id?
            classification = @.resolveLocalClassification(metric.id)
        if !classification and metric.externalId?
            classification = @.resolveLocalClassification(metric.externalId)
        
        # New fallback: check metric object itself
        if !classification and metric.classification
            classification = metric.classification

        return classification

    matchesConfiguredMetric: (configuredValue, metricId, metricExternalId, allowPrefix = true) ->
        return false unless configuredValue?
        normalizedConfig = configuredValue.toString().toLowerCase()
        normalizedMetricId = if metricId? then metricId.toString().toLowerCase() else null
        normalizedExternalId = if metricExternalId? then metricExternalId.toString().toLowerCase() else null

        matchesExact = (value) ->
            value? and value == normalizedConfig

        matchesPrefix = (value) ->
            return false unless allowPrefix and value?
            return true if value.indexOf("#{normalizedConfig}_") is 0
            if normalizedConfig is "commits"
                return true if value.indexOf("commitscontribution_") is 0
            if normalizedConfig is "modifiedlines"
                return true if value.indexOf("modifiedlinescontribution_") is 0
            return false

        return true if matchesExact(normalizedMetricId) or matchesExact(normalizedExternalId)
        return true if matchesPrefix(normalizedMetricId) or matchesPrefix(normalizedExternalId)
        return false

    loadProject: ->
        expectedSlug = @params.pslug

        if @projectService.project
            project = @projectService.project.toJS()
            if expectedSlug and project?.slug? and project.slug isnt expectedSlug
                console.warn "Metrics: Project mismatch, reloading", project.slug, expectedSlug
                return @projectService.setProjectBySlug(expectedSlug).then =>
                    @.loadProject()
        else if expectedSlug
            console.warn "Metrics: Project not loaded in service, attempting fallback load"
            return @projectService.setProjectBySlug(expectedSlug).then =>
                @.loadProject()
            .catch (err) =>
                console.error "Metrics: Failed to load project", err
                @scope.metricsView.error = "METRICS.LOAD_ERROR"
                @scope.metricsView.loading = false
                return @q.reject(err)
        else
            @scope.metricsView.error = "METRICS.LOAD_ERROR"
            @scope.metricsView.loading = false
            return @q.reject("Metrics: Missing project slug")

        @scope.projectId = project.id
        @scope.project = project
        @scope.projectSlug = project.slug
        @scope.$emit('project:loaded', project)

        defaultExternal = @metricsConfig.resolveExternalProjectId(project.slug)
        if !@scope.metricsAuth.externalProjectId
            @scope.metricsAuth.externalProjectId = defaultExternal

        return project

    bootstrapMetricsAccess: ->
        # No auth flow required: use project config to resolve IDs/provider
        @scope.metricsAuth.authenticated = true
        @scope.metricsAuth.checking = false
        @scope.metricsAuth.username = @scope.projectSlug or @scope.project?.slug
        @scope.metricsAuth.externalProjectId ?= @metricsConfig.resolveExternalProjectId(@scope.projectSlug)
        @.loadMetrics(true)

    loadMilestones: ->
        return unless @scope.projectId
        @rs.sprints.list(@scope.projectId)
            .then (data) =>
                milestones = data.milestones
                sorted = _.sortBy(milestones, "estimated_start")
                options = [
                    {id: null, name: "METRICS.SPRINT_GLOBAL", translate: true}
                ]
                
                for sprint in sorted
                    options.push({
                        id: sprint.id
                        name: sprint.name
                        dateFrom: sprint.estimated_start
                        dateTo: sprint.estimated_finish
                    })
                
                @scope.metricsView.sprintOptions = options
                
                # Select global (null) by default
                @$timeout =>
                    @scope.metricsView.teamHistoricalFilters.sprint = null
                    @scope.metricsView.teamHistoricalFilters.user = "all"
                    @scope.metricsView.teamHistoricalFilters.metric = "all"
                    @.applySprintFilter(@scope.metricsView.teamHistoricalFilters)
                    
                    @scope.metricsView.projectHistoricalFilters.sprint = null
                    @scope.metricsView.projectHistoricalFilters.metric = "all"
                    @.applySprintFilter(@scope.metricsView.projectHistoricalFilters)
                , 0
                    
            .catch (error) =>
                console.warn "Metrics: Unable to load milestones", error

    applySprintFilter: (filters) ->
        return unless filters
        
        sprintId = filters.sprint
        
        # Find selected sprint
        selectedSprint = _.find(@scope.metricsView.sprintOptions, {id: sprintId})
        
        if selectedSprint and selectedSprint.dateFrom and selectedSprint.dateTo
            filters.dateFrom = new Date(selectedSprint.dateFrom)
            filters.dateTo = new Date(selectedSprint.dateTo)
            # Reset preset if sprint is selected
            filters.preset = null
        else
            # Global or custom: reset dates if switching back to global
            if sprintId == null
                filters.dateFrom = null
                filters.dateTo = null
                filters.preset = null

    loginMetrics: ->
        return if @scope.metricsAuth.loading

        username = @scope.metricsAuth.form.username

        if !username
            @scope.metricsAuth.error = "METRICS.LOGIN_USERNAME_REQUIRED"
            return

        externalId = username or @scope.metricsAuth.externalProjectId or @metricsConfig.resolveExternalProjectId(@scope.projectSlug)
        payload = {
            username: username
            project: externalId
            source: @metricsProvider
        }

        @scope.metricsAuth.loading = true
        @scope.metricsAuth.error = null

        url = @urls.resolve("metrics-login")
        @http.post(url, payload, null, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}
                @scope.metricsAuth.authenticated = true
                @scope.metricsAuth.username = data.username or username
                @scope.metricsAuth.externalProjectId = externalId
                @scope.metricsAuth.form.username = @scope.metricsAuth.username
                @scope.metricsAuth.loading = false
                @.loadMetrics(true)
            .catch (error) =>
                console.error "✗ Login failed:", error
                @scope.metricsAuth.loading = false
                errorKey = error?.data?.error
                @scope.metricsAuth.error = @.resolveErrorKey(errorKey, "METRICS.LOGIN_ERROR_GENERIC")

    logoutMetrics: ->
        return if @scope.metricsAuth.loading

        @scope.metricsAuth.loading = true
        @scope.metricsAuth.error = null

        url = @urls.resolve("metrics-logout")
        payload =
            source: @metricsProvider
        @http.post(url, payload, null, {withCredentials: true})
            .then =>
                @scope.metricsAuth.loading = false
                @scope.metricsAuth.authenticated = false
                @scope.metricsAuth.username = null
                @scope.metricsAuth.externalProjectId = @metricsConfig.resolveExternalProjectId(@scope.projectSlug)
                @scope.metricsView.data = null
            .catch (error) =>
                console.error "Error logging out from metrics:", error
                @scope.metricsAuth.loading = false
                @scope.metricsAuth.error = @.resolveErrorKey(error?.data?.error, "METRICS.LOGOUT_ERROR")

    loadMetrics: (force = false) ->
        return if @scope.metricsView.loading and !force

        projectSlug = @scope.projectSlug or @params.pslug
        if !@scope.project and @projectService.project
            @scope.project = @projectService.project.toJS()
            @scope.projectId = @scope.project?.id

        if !projectSlug
            @scope.metricsView.error = "METRICS.LOAD_ERROR"
            @scope.metricsView.data = null
            @scope.metricsView.loading = false
            return

        @scope.projectSlug = projectSlug

        externalId = @scope.metricsAuth.externalProjectId or @metricsConfig.resolveExternalProjectId(projectSlug)

        params =
            project: projectSlug
            source: @metricsProvider

        if externalId
            params.external = externalId

        @scope.metricsView.loading = true
        @scope.metricsView.error = null
        @scope.metricsView.isNewProject = false
        @scope.metricsView.errors = {}
        @.resetTeamOverviewState()

        url = @urls.resolve("metrics")
        @http.get(url, params, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}

                payloadContext =
                    data: angular.copy(data)
                    project: @scope.project
                    scope: @scope

                transformedPayload = @metricsHooks.transformMetricsPayload(payloadContext)
                if transformedPayload isnt undefined
                    data = transformedPayload
                else if payloadContext?.data isnt undefined
                    data = payloadContext.data

                @resetUserColorAssignments()

                @scope.metricsAuth.externalProjectId = data.external_project_id or externalId

                metricsCategoriesData = data.metrics_categories or data.metricsCategories or {}
                @metricsCategoryPalettes = @.buildMetricCategoryPalettes(metricsCategoriesData)

                # Build quality factor id->name map for display purposes
                # The main metrics array contains quality factors with their names
                # Each quality factor has id (e.g., "modifiedlinescontribution") and name (e.g., "Modified Lines Contribution")
                allMetricsData = data.metrics or []
                @qualityFactorNamesMap = @.buildQualityFactorNamesMap(allMetricsData)

                studentsRaw = data.students
                
                # Pol Alcoverro added: Associate metrics with students using their identities
                # Gather all metrics including nested ones
                allMetrics = []
                collectMetrics = (arr) ->
                    return unless angular.isArray(arr)
                    for m in arr when m?
                        allMetrics.push(m)
                        if angular.isArray(m.metrics)
                            collectMetrics(m.metrics)
                
                collectMetrics(data.metrics or [])

                if studentsRaw and angular.isArray(studentsRaw)
                    for student in studentsRaw when student
                        # Get the student's TAIGA and GITHUB usernames
                        taigaUsername = student.identities?.TAIGA?.username
                        githubUsername = student.identities?.GITHUB?.username
                        baseUsername = student.username or student.name or student.displayName or student.id

                        # Filter metrics that belong to this student
                        studentMetrics = []
                        for metric in allMetrics when metric?
                            metricId = (metric.externalId or metric.id or "").toString().toLowerCase()
                            continue unless metricId.length > 0
                            
                            # Check if this metric belongs to the student
                            hasExplicitUser = metric.user == baseUsername or metric.resolvedUsername == baseUsername
                            matchesTaiga = taigaUsername and metricId.includes("_#{taigaUsername.toLowerCase()}")
                            matchesGithub = githubUsername and metricId.includes("_#{githubUsername.toLowerCase()}")
                            matchesBase = baseUsername and typeof baseUsername is "string" and metricId.includes("_#{baseUsername.toLowerCase()}")

                            if hasExplicitUser or matchesTaiga or matchesGithub or matchesBase
                                studentMetrics.push(metric)
                                metric.resolvedUsername = student.username or student.name or student.displayName or student.id or taigaUsername
                                metric.resolvedDisplayName = student.displayName or student.name or metric.resolvedUsername
                        
                        # Assign the filtered metrics to the student
                        student.metrics = studentMetrics
                # AUTO-DISCOVER MISSING MAPPINGS (Pol Alcoverro)
                # After resolving what we can from identities, learn the best possible username and display name for each suffix
                suffixToUsername = {}
                suffixToDisplayName = {}

                for m in allMetrics when m?
                    # Always prefer resolved/Taiga names over raw Github tags
                    u = m.resolvedUsername or m.student or m.user or m.username or m.owner
                    disp = m.resolvedDisplayName or m.student_display or m.studentDisplay or m.user_display or m.userDisplay or m.displayName
                    idStr = (m.externalId or m.id or "").toString().toLowerCase()
                    if idStr.includes("_")
                        parts = idStr.split("_")
                        if parts.length >= 2
                            suffix = parts.slice(1).join("_")
                            # Only overwrite if we found a "better" (likely more resolved) name
                            currU = suffixToUsername[suffix]
                            if u and (!currU or currU is suffix)
                                suffixToUsername[suffix] = u
                            if disp
                                suffixToDisplayName[suffix] = disp

                # Forcefully apply the best known identities to ALL metrics sharing the same suffix
                for m in allMetrics when m?
                    idStr = (m.externalId or m.id or "").toString().toLowerCase()
                    if idStr.includes("_")
                        parts = idStr.split("_")
                        if parts.length >= 2
                            suffix = parts.slice(1).join("_")
                            bestU = suffixToUsername[suffix]
                            bestDisp = suffixToDisplayName[suffix]
                            
                            if bestU
                                m.resolvedUsername = bestU
                                m.user = bestU
                            if bestDisp
                                m.resolvedDisplayName = bestDisp
                                m.userDisplayName = bestDisp
                        
                # End Pol Alcoverro added

                processedMetrics = @.processGessiMetrics(data.metrics or [])
                
                normalizedStudents = @.normalizeStudentsCollection(studentsRaw)
                
                processedUsers = @.processStudentsMetrics(normalizedStudents)
                
                # PRIMERO TOCA EXTRAER/MAPEAR USUARIOS (así se les hace el match y añade resolvedUsername a las métricas directas del payload)
                # ALWAYS extract any missing users found in the metrics that weren't explicitly in studentsRaw
                extractedUsers = @.extractUsersFromMetrics(data.metrics or [])
                for own uname, uData of extractedUsers
                    if not processedUsers[uname]?
                        processedUsers[uname] = uData

                processedUsersList = @.usersMetricsToArray(processedUsers)
                @.registerUserColors(processedUsersList)
                
                # Y ahora construimos los grupos sabiendo la info resuelta (el resolvedUsername)
                displayMetricGroups = @.buildMetricDisplayGroups(data.metrics or [])
                projectMetricsList = @.prepareProjectMetrics(data.metrics or [])

                hoursData = data.hours or {}
                hasHoursData = hoursData? and typeof hoursData is "object" and Object.keys(hoursData).length > 0
                hoursChart = if hasHoursData then @.prepareHoursPieData(hoursData) else null
                # Prepare strategic indicators for display
                processedStrategicIndicators = @.prepareStrategicIndicators(data.strategic_indicators or [])
                
                # Prepare quality factors for display
                processedQualityFactors = @.prepareQualityFactors(data.quality_factors or [])

                @.initializeTeamHistoricalUsers(processedUsersList)

                # Create visualizations for team view
                studentsOverallRadar = @.buildStudentsOverallRadar(processedUsersList)
                studentsClosedTasksBar = @.buildClosedTasksComparison(processedUsersList)

                viewData = {
                    metrics: processedMetrics,
                    usersMetrics: processedUsers,
                    usersMetricsList: processedUsersList,
                    rawMetrics: data.metrics or [],
                    projectMetrics: projectMetricsList,
                    rawStudents: studentsRaw,
                    suffixToDisplayName: suffixToDisplayName,
                    strategicIndicators: processedStrategicIndicators,
                    qualityFactors: processedQualityFactors,
                    projectMetricGroups: displayMetricGroups.project,
                    teamMetricGroups: displayMetricGroups.team,
                    hours: hoursData,
                    hoursChart: hoursChart,
                    studentsOverallRadar: studentsOverallRadar,
                    studentsClosedTasksBar: studentsClosedTasksBar,
                    metricsCategories: metricsCategoriesData,
                    historicalMetrics: {
                        userMetrics: {}
                        projectMetrics: {}
                        strategicMetrics: {}
                        qualityFactors: {}
                    },
                    lastReport: {}
                }

                viewContext =
                    viewData: viewData
                    rawPayload: data
                    project: @scope.project
                    scope: @scope

                transformedView = @metricsHooks.transformMetricsView(viewContext)

                if transformedView isnt undefined
                    @scope.metricsView.data = transformedView
                else if viewContext?.viewData isnt undefined
                    @scope.metricsView.data = viewContext.viewData
                else
                    @scope.metricsView.data = viewData

                @.initializeTeamOverviewState()
                @.applyStudentPolicy(projectSlug)

                @scope.metricsView.teamHistoricalSource = null
                @scope.metricsView.teamHistoricalCharts = []
                @scope.metricsView.projectHistoricalCharts = []

                @scope.metricsView.errors = data.errors or {}
                @scope.metricsView.isNewProject = data.is_new_project
                @scope.metricsView.loading = false
                
                # Load historical metrics after current metrics are loaded
                @.loadHistoricalMetrics()
                
                # Don't trigger digest, let Angular handle it naturally
            .catch (error) =>
                console.error "Error loading metrics:", error
                @scope.metricsView.loading = false
                @scope.metricsView.error = @.resolveErrorKey(error?.data?.error, "METRICS.LOAD_ERROR")
                @scope.metricsView.data = null
                @.resetTeamOverviewState()
                @scope.metricsView.teamHistoricalSource = null
                @scope.metricsView.teamHistoricalCharts = []
                @scope.metricsView.projectHistoricalCharts = []

    loadHistoricalMetrics: ->
        # For internal provider, skip authentication check
        # For external provider, require authentication
        console.log "[DEBUG] loadHistoricalMetrics called, authenticated:", @scope.metricsAuth?.authenticated, "provider:", @metricsProvider
        
        if @metricsProvider isnt "internal"
            return unless @scope.metricsAuth.authenticated
        
        return unless @scope.projectSlug

        projectSlug = @scope.projectSlug
        externalId = @scope.metricsAuth.externalProjectId or @metricsConfig.resolveExternalProjectId(projectSlug)

        params =
            project: projectSlug
            source: @metricsProvider

        if externalId
            params.external = externalId

        if @metricsProvider is "internal"
            params.refresh = true

        url = @urls.resolve("metrics-historical")
        console.log "[DEBUG] Fetching historical metrics from:", url, "params:", params
        
        @http.get(url, params, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}
                historicalData = data.historical_data || {}
                console.log "[DEBUG] Historical data received:", Object.keys(historicalData), "userMetrics keys:", Object.keys(historicalData.userMetrics || {})
                
                # Process historical data into user and project charts
                processedHistorical = @.processHistoricalData(historicalData)

                historicalContext =
                    data: processedHistorical
                    raw: historicalData
                    project: @scope.project
                    scope: @scope

                transformedHistorical = @metricsHooks.transformHistoricalPayload(historicalContext)
                if transformedHistorical isnt undefined
                    processedHistorical = transformedHistorical
                else if historicalContext?.data isnt undefined
                    processedHistorical = historicalContext.data

                
                # Update the view data with historical metrics
                if @scope.metricsView.data
                    @scope.metricsView.data.historicalMetrics = processedHistorical
                    # Force Angular to update the view - use $timeout to trigger digest cycle
                    @$timeout (->), 0
                    @.updateTeamHistoricalSource(processedHistorical)
                else
                    @scope.metricsView.data = {historicalMetrics: processedHistorical}
                    @$timeout (->), 0
                    @.updateTeamHistoricalSource(processedHistorical)
                
            .catch (error) =>
                console.error "Error loading historical metrics:", error
                if @scope.metricsView.data
                    @scope.metricsView.data.historicalMetrics = {
                        error: @.resolveErrorKey(error?.data?.error, "METRICS.HISTORICAL_LOAD_ERROR")
                    }
                @scope.metricsView.teamHistoricalSource = null
                @scope.metricsView.teamHistoricalCharts = []
                @scope.metricsView.projectHistoricalCharts = []

    normalizeStudentsCollection: (students) ->
        return [] unless students?

        if angular.isArray(students)
            return students

        if typeof students is "object"
            normalized = []

            # Handle payloads nested under a 'results' property
            if angular.isArray(students.results)
                return students.results

            for own username, metricsList of students
                normalized.push({
                    username: username
                    name: username
                    metrics: metricsList
                })
            return normalized

        return []

    normalizeCategoryKey: (name) ->
        return null unless name?
        key = name.toString().trim().toLowerCase()
        return if key.length then key else null

    buildMetricCategoryPalettes: (categoriesData) ->
        grouped = {}
        return grouped unless categoriesData?

        entries = []

        if angular.isArray(categoriesData)
            entries = categoriesData
        else if typeof categoriesData is "object"
            for own _, value of categoriesData when value?
                if angular.isArray(value)
                    entries = entries.concat(value)
                else
                    entries.push(value)

        for entry in entries when entry?
            nameKey = @.normalizeCategoryKey(entry.name or entry.category or entry.displayName)
            continue unless nameKey

            grouped[nameKey] ?= []
            upper = parseFloat(entry.upperThreshold)

            grouped[nameKey].push({
                color: entry.color or entry.hex or "#2563EB"
                upperThreshold: if isFinite(upper) then Math.max(0, upper) else null
                type: entry.type or null
                raw: entry
            })

        for nameKey, palette of grouped
            valid = palette.filter (item) -> item.upperThreshold? and isFinite(item.upperThreshold)
            if valid.length > 0
                valid.sort (a, b) ->
                    if a.upperThreshold < b.upperThreshold then -1
                    else if a.upperThreshold > b.upperThreshold then 1
                    else 0
                grouped[nameKey] = valid
            else
                grouped[nameKey] = palette.slice()

        grouped

    normalizeMetricValue: (rawValue) ->
        return 0 unless rawValue?

        value = rawValue

        if Array.isArray(value)
            # Look for the first usable entry in arrays like [{value: 0.7}]
            for item in value when item?
                if typeof item is "number"
                    value = item
                    break
                if typeof item is "string" and item.trim()? and !isNaN(parseFloat(item))
                    value = parseFloat(item)
                    break
                if typeof item is "object"
                    candidates = [item.value, item.first, item.percentage, item.percent, item.score]
                    for candidate in candidates when candidate?
                        if typeof candidate in ["number", "string"]
                            value = candidate
                            break
                    break if typeof value isnt "object"

        if typeof value is "object"
            candidates = [
                value.value
                value.first
                value.percentage
                value.percent
                value.score
                value.amount
                value.total
                value.current
            ]

            chosen = null
            for candidate in candidates when candidate?
                if typeof candidate in ["number", "string"]
                    chosen = candidate
                    break

            if chosen?
                value = chosen
            else
                for own _, candidateValue of value
                    if typeof candidateValue is "number"
                        value = candidateValue
                        break
                    if typeof candidateValue is "string" and candidateValue.trim()? and !isNaN(parseFloat(candidateValue))
                        value = parseFloat(candidateValue)
                        break

        if typeof value is "string"
            parsed = parseFloat(value)
            value = if isNaN(parsed) then 0 else parsed

        value = Number(value) or 0

        # Values coming from gessi-dashboard are typically ratios (0-1)
        if Math.abs(value) <= 1
            value = value * 100

        # Avoid negative percentages and clamp very large spikes
        value = Math.max(0, value)

        # Keep two decimal precision for display purposes
        return Math.round(value * 100) / 100

    buildMetricDetail: (metric) ->
        return null unless metric?

        normalizedValue = @.normalizeMetricValue(metric.value)
        resolvedId = metric.externalId or metric.id

        return {
            id: resolvedId
            name: metric.name or resolvedId
            value: normalizedValue
            rawValue: metric.value
            valueDescription: metric.value_description or metric.valueDescription
            date: metric.date or metric.timestamp or metric.updated_at or metric.lastUpdated
            description: metric.description
            qualityFactors: metric.qualityFactors or metric.quality_factors or []
        }

    processUsersMetrics: (rawData) ->
        processed = {}

        for username, metrics of rawData
            totalTasks = metrics.totalTasks ? metrics.total_tasks ? 0
            completedTasks = metrics.completedTasks ? metrics.completed_tasks ? 0
            totalUS = metrics.totalUS ? metrics.total_us ? 0
            completedUS = metrics.completedUS ? metrics.completed_us ? 0

            tasksPercentage = if totalTasks > 0 then Math.round((completedTasks / totalTasks) * 100) else 0
            usPercentage = if totalUS > 0 then Math.round((completedUS / totalUS) * 100) else 0

            processed[username] = {
                totalTasks: totalTasks
                completedTasks: completedTasks
                totalUS: totalUS
                completedUS: completedUS
                tasksPercentage: tasksPercentage
                usPercentage: usPercentage
            }

        @.decorateUsersMetrics(processed)

        return processed

    decorateUsersMetrics: (users) ->
        return users unless users

        for username, data of users
            continue unless username and data
            data.radarData = @.buildUserRadarData(username, data)
        return users

    buildUserRadarData: (username, userData) ->
        return null unless username and userData

        assignedTasks = Number(userData.assignedTasks) or 0
        closedTasks = Number(userData.closedTasks) or 0
        commits = Number(userData.commits) or 0
        modifiedLines = Number(userData.modifiedLines) or 0

        if isNaN(assignedTasks) then assignedTasks = 0
        if isNaN(closedTasks) then closedTasks = 0
        if isNaN(commits) then commits = 0
        if isNaN(modifiedLines) then modifiedLines = 0

        @.registerUserColors([username])
        colorPalette = @.resolveUserColor(username)
        backgroundColor = colorPalette?.fill or 'rgba(59, 130, 246, 0.26)'
        borderColor = colorPalette?.border or '#3B82F6'

        radarData = {
            labels: [
                'Tasks'
                'Closed Tasks'
                'Commits'
                'Modified Lines'
            ]
            datasets: [{
                label: username
                data: [
                    assignedTasks
                    closedTasks
                    commits
                    modifiedLines
                ]
                backgroundColor: backgroundColor
                borderColor: borderColor
                borderWidth: 2
                pointBackgroundColor: borderColor
                pointBorderColor: '#ffffff'
                pointHoverBackgroundColor: '#ffffff'
                pointHoverBorderColor: borderColor
            }]
        }

        return radarData

    processStudentsMetrics: (studentsRaw) ->
        processed = {}

        students = @.normalizeStudentsCollection(studentsRaw)
        return processed unless students?.length

        for student in students when student
            username = student?.username or student?.name or student?.displayName or student?.id
            unless username? and username.toString().trim().length
                username = student?.identities?.TAIGA?.username or student?.identities?.GITHUB?.username
            continue unless username? and username.toString().trim().length

            normalizedName = username.toString().trim()
            metricsList = student.metrics or student.metrics_list or student.metricsList or []

            if !angular.isArray(metricsList) and metricsList? and typeof metricsList is "object"
                metricsObject = metricsList
                metricsList = (Object.keys(metricsObject or {}).map (key) -> metricsObject[key])

            metricsList = (metricsList or []).filter (metric) -> metric?

            entry = {
                username: normalizedName
                displayName: student?.displayName or student?.name or normalizedName
                assignedTasks: 0
                closedTasks: 0
                commits: 0
                modifiedLines: 0
                totalTasks: 0
                completedTasks: 0
                totalUS: 0
                completedUS: 0
                tasksPercentage: 0
                usPercentage: 0
                metricsDetails: []
                rawMetrics: if angular.isArray(metricsList) then metricsList.slice() else []
            }

            seenMetricIds = {}

            for metric in metricsList when metric?.id?
                metricKey = metric.id.toString()
                next if seenMetricIds[metricKey]

                detail = @.buildMetricDetail(metric)
                if detail?
                    entry.metricsDetails.push(detail)
                seenMetricIds[metricKey] = true

                metricId = metricKey.toLowerCase()
                metricValue = detail?.value
                metricValue ?= @.normalizeMetricValue(metric.value)

                metricId = metricKey.toLowerCase()
                metricValue = detail?.value
                metricValue ?= @.normalizeMetricValue(metric.value)

                configuredKeys = @metricsConfig.teamMetricsOrder or []
                if !angular.isArray(configuredKeys) or configuredKeys.length is 0
                    configuredKeys = [
                        "assignedtasks"
                        "closedtasks"
                        "completedtasks"
                        "commits"
                        "modifiedlines"
                        "linesmodified"
                        "totalus"
                        "completedus"
                        "closedus"
                    ]

                for rawKey in configuredKeys when rawKey?
                    configuredKey = rawKey.toString().toLowerCase()
                    continue unless metricId.indexOf(configuredKey) isnt -1
                    
                    console.log "✅ Metric match: #{metricId} contains '#{configuredKey}', value=#{metricValue}"

                    if configuredKey is "assignedtasks"
                        entry.assignedTasks = metricValue
                        entry.totalTasks = Math.max(entry.totalTasks, metricValue)
                    else if configuredKey is "closedtasks" or configuredKey is "completedtasks"
                        entry.closedTasks = metricValue
                        entry.completedTasks = metricValue
                        entry.tasksPercentage = metricValue
                    else if configuredKey is "commits" or configuredKey is "commitscontribution"
                        entry.commits = metricValue
                    else if configuredKey is "modifiedlines" or configuredKey is "linesmodified" or configuredKey is "modifiedlinescontribution"
                        entry.modifiedLines = metricValue
                    else if configuredKey is "totalus"
                        entry.totalUS = metricValue
                    else if configuredKey is "completedus" or configuredKey is "closedus"
                        entry.completedUS = metricValue
                        entry.usPercentage = metricValue

            # Calcular porcentajes
            if entry.totalTasks > 0 and entry.completedTasks > 0
                ratio = entry.completedTasks
                if entry.completedTasks > entry.totalTasks and entry.totalTasks > 0
                    ratio = (entry.completedTasks / entry.totalTasks) * 100
                entry.tasksPercentage = Math.min(100, Math.round(ratio * 100) / 100) if ratio?

            if entry.totalUS > 0 and entry.completedUS > 0
                ratioUS = entry.completedUS
                if entry.completedUS > entry.totalUS and entry.totalUS > 0
                    ratioUS = (entry.completedUS / entry.totalUS) * 100
                entry.usPercentage = Math.min(100, Math.round(ratioUS * 100) / 100) if ratioUS?

            entry.metricsDetails.sort (a, b) ->
                aName = (a?.name or "").toString().toLowerCase()
                bName = (b?.name or "").toString().toLowerCase()
                if aName < bName then -1 else if aName > bName then 1 else 0

            processed[normalizedName] = entry

        @.decorateUsersMetrics(processed)

        return processed

    usersMetricsToArray: (usersObject) ->
        return [] unless usersObject

        list = []
        for username, data of usersObject
            continue unless username and data

            data.radarData ?= @.buildUserRadarData(username, data)

            cloned = angular.extend({}, data)
            cloned.username = username
            cloned.displayName = data.displayName or username
            cloned.radarData = data.radarData

            if angular.isArray(data.metricsDetails)
                cloned.metricsDetails = data.metricsDetails.slice()
            else
                cloned.metricsDetails = []

            if cloned.metricsDetails.length is 0 and angular.isArray(data.rawMetrics)
                details = []
                seen = {}
                for metric in data.rawMetrics when metric?.id?
                    detail = @.buildMetricDetail(metric)
                    continue unless detail?
                    continue if seen[detail.id]
                    seen[detail.id] = true
                    details.push(detail)
                cloned.metricsDetails = details if details.length > 0

            list.push(cloned)

        list.sort (a, b) ->
            aName = (a.username or "").toString().toLowerCase()
            bName = (b.username or "").toString().toLowerCase()
            if aName < bName then -1 else if aName > bName then 1 else 0

        return list

    processGessiMetrics: (metricsArray) ->
        # Process gessi-dashboard metrics array into organized structure
        processed = {
            byCategory: {}
            byUser: {}
            all: metricsArray
        }

        for metric in metricsArray
            # Group by quality factor (category)
            if metric.qualityFactors and metric.qualityFactors.length > 0
                for factor in metric.qualityFactors
                    processed.byCategory[factor] ?= []
                    processed.byCategory[factor].push(metric)

            # Extract user-specific metrics
            identifierForParsing = (metric.externalId or metric.id or "").toString().toLowerCase()
            if identifierForParsing.includes("_")
                parts = identifierForParsing.split("_")
                if parts.length >= 2
                    metricType = parts[0]
                    extractedUserName = parts[1..].join("_")
                    userName = metric.resolvedUsername or extractedUserName
                    
                    processed.byUser[userName] ?= []
                    processed.byUser[userName].push(metric)

        return processed

    # Get normalized usernames from project members for filtering external users
    getProjectMemberUsernames: ->
        members = @scope.project?.members or []
        usernames = {}
        
        for member in members when member?
            # Extract username from various possible fields
            username = member.username or member.user or member.email?.split('@')[0]
            continue unless username?
            
            # Store normalized (lowercase) version as key, original as value
            normalized = username.toString().trim().toLowerCase()
            continue unless normalized.length
            
            usernames[normalized] = {
                original: username
                fullName: member.full_name or member.full_name_display or username
                email: member.email
            }
            
            # Also add full_name variants for matching
            if member.full_name
                fullNameNormalized = member.full_name.toString().trim().toLowerCase().replace(/\s+/g, '_')
                usernames[fullNameNormalized] = usernames[normalized]
                # Also without underscores
                fullNameNoSpace = member.full_name.toString().trim().toLowerCase().replace(/\s+/g, '')
                usernames[fullNameNoSpace] = usernames[normalized]
                # Add partial name combos: first word + each other word, and individual words
                # Handles GitHub usernames that combine parts of a multi-word full name
                nameParts = member.full_name.toString().trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9\s]/g, '').split(/\s+/).filter((p) -> p.length >= 3)
                if nameParts.length >= 2
                    firstNamePart = nameParts[0]
                    for otherPart in nameParts[1..]
                        combo = firstNamePart + otherPart
                        usernames[combo] ?= usernames[normalized] if combo.length >= 6
                for namePart in nameParts
                    usernames[namePart] ?= usernames[normalized] if namePart.length >= 4

            # Include explicit identity usernames if available (TAIGA / GITHUB)
            taigaId = member.identities?.TAIGA?.username
            githubId = member.identities?.GITHUB?.username
            if taigaId
                taigaNorm = taigaId.toString().trim().toLowerCase()
                usernames[taigaNorm] = usernames[normalized]
                usernames[taigaNorm.replace(/[^a-z0-9]/g, '')] = usernames[normalized]
                usernames[normalized].taiga = taigaId
            if githubId
                ghNorm = githubId.toString().trim().toLowerCase()
                usernames[ghNorm] = usernames[normalized]
                usernames[ghNorm.replace(/[^a-z0-9]/g, '')] = usernames[normalized]
                usernames[normalized].github = githubId
        
        return usernames

    # Check if an extracted username from external metrics is valid (not a false positive pattern)
    isValidExternalUsername: (extractedUsername) ->
        return false unless extractedUsername?
        
        normalized = extractedUsername.toString().trim().toLowerCase()
        return false unless normalized.length
        
        # List of patterns that look like usernames but are actually metric type suffixes
        invalidPatterns = [
            'anonymous'           # commits_anonymous - not a real user
            'sd'                  # commits_sd (standard deviation) 
            'taskreference'       # commits_taskreference
            'contribution'        # modifiedlines_contribution (aggregate metric)
            'management'          # commits_management
            'total'               # any _total metrics
            'all'                 # any _all metrics
            'unassigned'          # unassigned metrics
            'unknown'             # unknown user
            'system'              # system metrics
            'team'                # team aggregate
            'project'             # project aggregate
            'average'             # average metrics
            'mean'                # mean metrics
            'median'              # median metrics
            'deviation'           # deviation metrics
            'variance'            # variance metrics
        ]
        
        return false if invalidPatterns.indexOf(normalized) isnt -1
        
        # Also exclude if it's only numbers or very short
        return false if /^\d+$/.test(normalized)
        return false if normalized.length < 2
        
        return true

    # Match extracted username against project members (fuzzy matching)
    matchUsernameToMember: (extractedUsername, projectMembers) ->
        return null unless extractedUsername? and projectMembers?
        
        normalized = extractedUsername.toString().trim().toLowerCase()
        return null unless normalized.length

        # Strip all non-alphanumeric characters for clean comparison
        cleanString = (str) -> str.replace(/[^a-z0-9]/g, '')
        cleanExtracted = cleanString(normalized)
        
        # Direct match
        if projectMembers[normalized]
            return projectMembers[normalized]
        
        # Try partial match (username contains or is contained in member name)
        for memberKey, memberData of projectMembers
            # Check if extracted username contains the member key or vice versa
            if normalized.indexOf(memberKey) isnt -1 or memberKey.indexOf(normalized) isnt -1
                return memberData
            # Also check with fully cleaned strings (no dots, no separators)
            cleanMember = cleanString(memberKey)
            if cleanExtracted and cleanMember and (cleanExtracted.indexOf(cleanMember) isnt -1 or cleanMember.indexOf(cleanExtracted) isnt -1)
                return memberData
        
        return null

    extractUsersFromMetrics: (metricsArray) ->
        # Extract user metrics from gessi-dashboard format
        users = {}
        
        # Get project members for filtering
        projectMembers = @.getProjectMemberUsernames()
        hasProjectMembers = projectMembers? and Object.keys(projectMembers).length > 0
        
        # Track normalized usernames to merge case-insensitive duplicates
        normalizedUserMap = {}
        
        for metric in metricsArray when metric?
            identifierForParsing = (metric.externalId or metric.id or "").toString().toLowerCase()

            # Look for user-specific metrics
            if identifierForParsing and (identifierForParsing.includes("assignedtasks_") or 
                             identifierForParsing.includes("closedtasks_") or
                             identifierForParsing.includes("commits_") or
                             identifierForParsing.includes("commitscontribution_") or
                             identifierForParsing.includes("modifiedlines_") or
                             identifierForParsing.includes("modifiedlinescontribution_") or
                             identifierForParsing.includes("completedus_") or
                             identifierForParsing.includes("totalus_"))
                
                parts = identifierForParsing.split("_")
                if parts.length >= 2
                    metricType = parts[0]
                    extractedUserName = parts[1..].join("_")
                    
                    # Use predefined identity mapping if available
                    if metric.resolvedUsername
                        canonicalUsername = metric.resolvedUsername
                        displayName = metric.resolvedDisplayName or metric.resolvedUsername
                        normalizedKey = canonicalUsername.toString().trim().toLowerCase()
                    else
                        # Validate: exclude false positive patterns like 'anonymous', 'sd', etc.
                        continue unless @.isValidExternalUsername(extractedUserName)
                        
                        # If we have project members, filter by membership
                        resolvedMember = null
                        if hasProjectMembers
                            resolvedMember = @.matchUsernameToMember(extractedUserName, projectMembers)

                            if not resolvedMember and metric.name
                                console.log "[DEBUG METRICS] Evaluando usuario desconocido: '#{extractedUserName}' -> metric.name original: '#{metric.name}'"
                                realName = metric.name.toString()
                                realName = realName.replace(/\s+(commits contribution|commits|modified lines contribution|modified lines|closed tasks|tasks)$/i, "")
                                
                                realName = realName.trim()
                                
                                cleanRealName = realName.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]/g, '')
                                
                                console.log "[DEBUG METRICS] Nombre extraído y limpiado: '#{realName}' -> '#{cleanRealName}'"

                                for key, member of projectMembers
                                    memberFullNameClean = (member.fullName or "").toString().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]/g, '')
                                    if memberFullNameClean
                                        # Hacemos un include por si a caso uno usa 2 apellidos y en el otro sitio 1 solo, o el nombre está del revés
                                        if memberFullNameClean == cleanRealName or memberFullNameClean.includes(cleanRealName) or cleanRealName.includes(memberFullNameClean)
                                            console.log "[DEBUG METRICS] MATCH ENCONTRADO! '#{extractedUserName}' coincide con miembro '#{member.fullName}' (#{memberFullNameClean})"
                                            resolvedMember = member
                                            break
                                        else
                                            # Word-by-word matching: handles middle names omitted in external dashboard
                                            # e.g., "john smith" matches "John Middle Smith Lastname"
                                            normalizeWord = (w) -> w.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]/g, '')
                                            externalWords = realName.split(/\s+/).map(normalizeWord).filter (w) -> w.length > 1
                                            memberWords = (member.fullName or "").split(/\s+/).map(normalizeWord).filter (w) -> w.length > 1
                                            if externalWords.length > 0 and memberWords.length > 0 and externalWords.every((w) -> memberWords.indexOf(w) isnt -1)
                                                console.log "[DEBUG METRICS] MATCH WORD-BY-WORD! '#{extractedUserName}' -> '#{member.fullName}'"
                                                resolvedMember = member
                                                break

                                if not resolvedMember
                                    console.log "[DEBUG METRICS] ERROR: No se ha encontrado ningún miembro en Taiga que coincida con '#{cleanRealName}'."


                            # Skip if not a project member
                            continue unless resolvedMember?
                        
                        # Normalize username for deduplication (case-insensitive)
                        if resolvedMember?
                            canonicalUsername = resolvedMember.original
                            displayName = resolvedMember.fullName
                            normalizedKey = canonicalUsername.toString().trim().toLowerCase()
                        else
                            canonicalUsername = extractedUserName
                            displayName = extractedUserName
                            normalizedKey = extractedUserName.toString().trim().toLowerCase()
                    
                    # Check if we already have this user under a different case variant
                    if normalizedUserMap[normalizedKey]?
                        userName = normalizedUserMap[normalizedKey]
                    else
                        userName = canonicalUsername
                        normalizedUserMap[normalizedKey] = userName

                    metric.resolvedUsername = userName
                    metric.resolvedDisplayName = displayName
                    
                    users[userName] ?= {
                        username: userName
                        assignedTasks: 0
                        closedTasks: 0
                        commits: 0
                        modifiedLines: 0
                        totalTasks: 0
                        completedTasks: 0
                        totalUS: 0
                        completedUS: 0
                        tasksPercentage: 0
                        usPercentage: 0
                        metricsDetails: []
                        rawMetrics: []
                        displayName: displayName  # Use resolved display name from project member
                    }

                    detail = @.buildMetricDetail(metric)
                    normalizedValue = detail?.value
                    normalizedValue ?= @.normalizeMetricValue(metric.value)

                    # Store the raw metric object for display
                    if detail?
                        existingIds = users[userName]._metricsIds ?= {}
                        unless existingIds[detail.id]
                            users[userName].metricsDetails.push(detail)
                            existingIds[detail.id] = true
                    users[userName].rawMetrics ?= []
                    users[userName].rawMetrics.push(metric)
                    
                    # Map metric types to user properties
                    # Values are percentages (0-1), we multiply by 100 for display
                    if metricType == "assignedtasks"
                        users[userName].assignedTasks = normalizedValue
                        users[userName].totalTasks = Math.max(users[userName].totalTasks, normalizedValue)
                    else if metricType == "closedtasks" or metricType == "completedtasks"
                        users[userName].closedTasks = normalizedValue
                        users[userName].completedTasks = normalizedValue
                        users[userName].tasksPercentage = normalizedValue
                    else if metricType == "commits" or metricType == "commitscontribution"
                        users[userName].commits = normalizedValue
                    else if metricType == "modifiedlines" or metricType == "modifiedlinescontribution"
                        users[userName].modifiedLines = normalizedValue
                    else if metricType == "totalus"
                        # totalus is an absolute count, not a ratio - use raw value
                        rawValue = if typeof metric.value is 'number' then metric.value else parseFloat(metric.value) or 0
                        users[userName].totalUS = rawValue
                    else if metricType == "completedus" or metricType == "closedus"
                        # completedus is a ratio (closed/assigned), use normalized value like other metrics
                        users[userName].completedUS = normalizedValue
                        users[userName].usPercentage = normalizedValue

                    if users[userName].totalTasks > 0 and users[userName].completedTasks > 0
                        ratio = users[userName].completedTasks
                        if users[userName].completedTasks > users[userName].totalTasks and users[userName].totalTasks > 0
                            ratio = (users[userName].completedTasks / users[userName].totalTasks) * 100
                        users[userName].tasksPercentage = Math.min(100, Math.round(ratio * 100) / 100)
                    if users[userName].totalUS > 0 and users[userName].completedUS > 0
                        ratioUS = users[userName].completedUS
                        if users[userName].completedUS > users[userName].totalUS and users[userName].totalUS > 0
                            ratioUS = (users[userName].completedUS / users[userName].totalUS) * 100
                        users[userName].usPercentage = Math.min(100, Math.round(ratioUS * 100) / 100)

                    # Attempt to resolve display name from metric name if missing
                    if !users[userName].displayName and metric.name
                         name = metric.name.toString()
                         name = name.replace(/\s+(commits contribution|commits|modified lines contribution|modified lines|closed tasks|tasks|user stories|completed user stories)$/i, "")
                         if name.length > 0
                             users[userName].displayName = name

        # Cleanup helper metadata
        for userName, userData of users when userData?._metricsIds?
            delete userData._metricsIds
        
        for userName, userData of users when angular.isArray(userData?.metricsDetails)
            userData.metricsDetails.sort (a, b) ->
                aName = (a?.name or "").toString().toLowerCase()
                bName = (b?.name or "").toString().toLowerCase()
                if aName < bName then -1 else if aName > bName then 1 else 0

        @.decorateUsersMetrics(users)

        return users
    
    # Format user metrics for radar chart visualization
    prepareUserRadarData: (username, userData) ->
        return null unless userData
        userData.radarData ?= @.buildUserRadarData(username, userData)
        return userData.radarData
    
    # Prepare radar chart with multiple users
    prepareMultiUserRadarData: (usersData) ->
        return null unless usersData
        
        datasets = []
        usernames = []
        datasetMap = usersData

        if angular.isArray(usersData)
            datasetMap = {}
            for dataEntry, idx in usersData when dataEntry?
                username = dataEntry.username or dataEntry.displayName or dataEntry.name or "User #{idx + 1}"
                datasetMap[username] = dataEntry
        else if typeof usersData isnt "object"
            return null

        usernames = Object.keys(datasetMap)
        usernames.sort (a, b) -> a.toString().localeCompare(b.toString())

        @.registerUserColors(usernames)

        for username in usernames
            userData = datasetMap[username]
            colorPalette = @.resolveUserColor(username)
            borderColor = colorPalette?.border or '#3B82F6'
            fillColor = colorPalette?.fill or 'rgba(59, 130, 246, 0.26)'
            datasets.push({
                label: username
                data: [
                    userData?.assignedTasks || 0
                    userData?.closedTasks || 0
                    userData?.commits || 0
                    userData?.modifiedLines || 0
                ]
                backgroundColor: fillColor
                borderColor: borderColor
                borderWidth: 2
                pointBackgroundColor: borderColor
                pointBorderColor: '#ffffff'
                pointHoverBackgroundColor: '#ffffff'
                pointHoverBorderColor: borderColor
            })
        
        return {
            labels: [
                'Tasks'
                'Closed Tasks'
                'Commits'
                'Modified Lines'
            ]
            datasets: datasets
        }

    applyStudentPolicy: (projectSlug) ->
        return unless projectSlug
        url = @urls.resolve("academics-metrics-policies")
        @http.get(url, {project_slug: projectSlug}).then (response) =>
            policies = response?.data
            return unless angular.isArray(policies) and policies.length > 0
            policy = policies[0]

            visibleIds   = policy.visible_to_students_metric_ids or []
            allowDrilldown = if policy.allow_student_drilldown? then policy.allow_student_drilldown else true

            unless allowDrilldown
                @scope.availableTabs = @scope.availableTabs.filter (t) -> t.id isnt 'team'
                if @scope.metricsView.activeTab is 'team'
                    @scope.metricsView.activeTab = 'project'

            return unless visibleIds.length > 0

            isVisible = (metricId) ->
                return true unless metricId
                mid = metricId.toString().toLowerCase()
                for base in visibleIds
                    b = base.toString().toLowerCase()
                    return true if mid is b or mid.indexOf(b + "_") is 0
                false

            data = @scope.metricsView.data
            return unless data

            if angular.isArray(data.projectMetrics)
                data.projectMetrics = data.projectMetrics.filter (m) ->
                    return true unless m
                    isVisible(m.id or m.externalId)

            if angular.isArray(data.teamMetricGroups)
                data.teamMetricGroups = data.teamMetricGroups.map (group) ->
                    return group unless group and angular.isArray(group.metrics)
                    filtered = group.metrics.filter (m) ->
                        return true unless m
                        isVisible(m.id or m.externalId)
                    angular.extend({}, group, {metrics: filtered})
                .filter (group) -> group and group.metrics and group.metrics.length > 0

            if angular.isArray(data.usersMetricsList)
                for user in data.usersMetricsList when user?
                    if angular.isArray(user.metrics)
                        user.metrics = user.metrics.filter (m) ->
                            return true unless m
                            isVisible(m.id or m.externalId)
        .catch -> # Silently ignore: project not linked to any edition

    prepareProjectMetrics: (metricsArray) ->
        return [] unless angular.isArray(metricsArray)

        metricsById = {}
        for metric in metricsArray
            continue unless metric
            # Skip user-scoped metrics (they belong in Team view)
            # BUT if scope is explicitly 'team', treat it as project metric regardless of ID pattern
            isExplicitTeamScope = (metric.scope == 'team')
            
            unless isExplicitTeamScope
                isUserMetric = @.isUserMetricId(metric.id) or @.isUserMetricId(metric.externalId)
                continue if isUserMetric

            if metric.externalId
                metricsById[metric.externalId.toLowerCase()] = metric
            if metric.id
                metricsById[metric.id.toString().toLowerCase()] = metric

        collected = []
        seenIds = {}

        addMetricEntry = (metric) =>
            # Respect explicit team scope
            isExplicitTeamScope = (metric?.scope == 'team')
            unless isExplicitTeamScope
                return if @.isUserMetricId(metric?.id) or @.isUserMetricId(metric?.externalId)
            entry = @.buildProjectMetricEntry(metric)
            if entry
                collected.push(entry)
                if metric.id?
                    seenIds[metric.id.toString().toLowerCase()] = true
                if metric.externalId?
                    seenIds[metric.externalId.toLowerCase()] = true

        projectOrder = @localConfig?.projectMetricsOrder
        unless angular.isArray(projectOrder) and projectOrder.length
            projectOrder = @metricsConfig.projectMetricsOrder or []
        for metricId in projectOrder
            normalizedId = metricId.toLowerCase()
            metric = metricsById[normalizedId]
            unless metric
                metric = _.find metricsArray, (candidate) =>
                    @.matchesConfiguredMetric(metricId, candidate.id, candidate.externalId, false)
                unless metric
                    continue

            classification = @.resolveMetricClassificationValue(metric)
            if classification is 'hidden'
                continue
            if classification is 'team'
                continue

            globalHidden = false
            if @metricsConfig.metricClassifications?[normalizedId] is 'hidden'
                globalHidden = true
            else if metric.externalId and @metricsConfig.metricClassifications?[metric.externalId.toLowerCase()] is 'hidden'
                globalHidden = true

            if globalHidden and classification isnt 'project'
                continue

            addMetricEntry(metric)

        if @localConfig?.classification
            for metric in metricsArray when metric?
                classification = @.resolveMetricClassificationValue(metric)
                continue unless classification is 'project'
                normalizedMetricId = null
                if metric.id?
                    normalizedMetricId = metric.id.toString().toLowerCase()
                else if metric.externalId?
                    normalizedMetricId = metric.externalId.toLowerCase()
                if normalizedMetricId and seenIds[normalizedMetricId]
                    continue
                addMetricEntry(metric)

        # Fallback: if no metrics were collected from order, add all non-user metrics
        # This ensures external provider metrics are shown even without explicit configuration
        if collected.length is 0 or Object.keys(metricsById).length > collected.length
            for metric in metricsArray when metric?
                continue unless metric.id? or metric.externalId?
                
                # Respect explicit team scope
                isExplicitTeamScope = (metric.scope == 'team')
                unless isExplicitTeamScope
                    isUserMetric = @.isUserMetricId(metric.id) or @.isUserMetricId(metric.externalId)
                    continue if isUserMetric
                
                normalizedMetricId = null
                if metric.id?
                    normalizedMetricId = metric.id.toString().toLowerCase()
                else if metric.externalId?
                    normalizedMetricId = metric.externalId.toLowerCase()
                
                continue if normalizedMetricId and seenIds[normalizedMetricId]
                
                classification = @.resolveMetricClassificationValue(metric)
                continue if classification is 'hidden'
                continue if classification is 'team'
                
                addMetricEntry(metric)


        context =
            metrics: collected
            rawMetrics: metricsArray
            project: @scope.project
            scope: @scope

        transformed = @metricsHooks.transformProjectMetrics(context)

        if transformed isnt undefined and angular.isArray(transformed)
            finalMetrics = transformed
        else if angular.isArray(context.metrics)
            finalMetrics = context.metrics
        else
            finalMetrics = collected

        return @.scaleProjectMetricsByProjectMax(finalMetrics)

    resolveMetricCategoryColor: (categoryName, percentValue) ->
        return null unless categoryName?
        key = @.normalizeCategoryKey(categoryName)
        palette = if key then @metricsCategoryPalettes?[key] else null
        return null unless palette? and palette.length

        percent = Number(percentValue)
        percent = 0 unless isFinite(percent)
        ratio = Math.max(0, percent) / 100

        matchedColor = null

        for item in palette when item?.upperThreshold? and isFinite(item.upperThreshold)
            if ratio <= item.upperThreshold + 1e-9
                matchedColor = item.color
                break

        unless matchedColor?
            matchedColor = (palette[palette.length - 1]?.color) or palette[0]?.color

        matchedColor or null

    buildMetricCategorySegments: (categoryName) ->
        return null unless categoryName?
        key = @.normalizeCategoryKey(categoryName)
        palette = if key then @metricsCategoryPalettes?[key] else null
        return null unless palette? and palette.length

        segments = []
        lastThreshold = 0

        for entry in palette when entry?
            upper = Number(entry.upperThreshold)
            continue unless isFinite(upper)

            clamped = Math.max(lastThreshold, Math.min(Math.max(upper, 0), 1))
            segmentRatio = clamped - lastThreshold
            continue unless segmentRatio > 0

            segments.push({
                color: entry.color or "#2563EB"
                value: segmentRatio
                upperThreshold: clamped
            })

            lastThreshold = clamped

        if lastThreshold < 1
            remainderRatio = 1 - lastThreshold
            if remainderRatio > 0
                fallbackColor = palette[palette.length - 1]?.color or "#CBD5F5"
                segments.push({
                    color: fallbackColor
                    value: remainderRatio
                    upperThreshold: 1
                })

        if segments.length then segments else null

    # Extract metric category from user metric ID
    # E.g., "user_closed_tasks_alice" -> "closed_tasks"
    # E.g., "task_completion_adriaguilera" -> "task_completion"
    # E.g., "story_points_pol" -> "story_points"
    extractMetricCategoryFromId: (metricId) ->
        return null unless metricId?
        
        lowerId = metricId.toString().toLowerCase()
        
        # 1. Specialized internal metrics patterns (check prefixes first to avoid generic matches)
        if lowerId.indexOf('user_closed_tasks') is 0 or lowerId.indexOf('closedtasks_') is 0 or lowerId.indexOf('completedtasks_') is 0
            return 'closed_tasks'
        if lowerId.indexOf('user_story_points') is 0 or lowerId.indexOf('totalus_') is 0
            return 'story_points'
        if lowerId.indexOf('user_stories_closed') is 0 or lowerId.indexOf('completedus_') is 0
            return 'stories_closed'
        if lowerId.indexOf('user_commits') is 0 or lowerId.indexOf('commits_') is 0
            return 'commits'
        if lowerId.indexOf('commitscontribution_') is 0
            return 'commitscontribution'
        if lowerId.indexOf('user_assigned_tasks') is 0 or lowerId.indexOf('assignedtasks_') is 0
            return 'tasks'
        if lowerId.indexOf('user_modified_lines') is 0 or lowerId.indexOf('modifiedlines_') is 0
            return 'modified_lines'
        if lowerId.indexOf('modifiedlinescontribution_') is 0
            return 'modifiedlinescontribution'
        if lowerId.indexOf('tasksratio_') is 0
            return 'tasks_ratio'

        # 2. Generic format: task_completion_username, story_points_username, etc.
        # Extract the metric type (first part before second underscore or hyphen)
        parts = lowerId.split('_')
        if parts.length >= 2
            # For "task_completion_user" or "story_points_user"
            metricType = parts[0] + '_' + parts[1].split('-')[0]
            
            # Map metric types to display categories
            categoryMap =
                'task_completion': 'closed_tasks'
                'tasks_assigned': 'tasks'
                'story_points': 'story_points'
                'stories_closed': 'stories_closed'
                'commits_count': 'commits'
                'lines_modified': 'modified_lines'
                'code_contributions': 'modified_lines'
            
            if categoryMap[metricType]
                return categoryMap[metricType]
            
            # If not in map, return the metric type itself
            return metricType
        
        null

    isUserMetricId: (metricId) ->
        return false unless metricId?

        lowerId = metricId.toString().toLowerCase()
        
        # New patterns: task_completion_username, story_points_username, etc.
        newPatterns = [
            "task_completion_"
            "tasks_assigned_"
            "story_points_"
            "stories_closed_"
            "commits_count_"
            "lines_modified_"
            "code_contributions_"
        ]
        
        # Old patterns
        oldPrefixes = [
            "assignedtasks_"
            "closedtasks_"
            "completedtasks_"
            "commits_"
            "commitscontribution_"
            "modifiedlines_"
            "modifiedlinescontribution_"
            "completedus_"
            "totalus_"
            "tasksratio_"
        ]
        
        isNewPattern = newPatterns.some (prefix) -> lowerId.indexOf(prefix) is 0
        isOldPattern = oldPrefixes.some (prefix) -> lowerId.indexOf(prefix) is 0
        isUserPattern = isNewPattern or isOldPattern
        
        # If the ID matches user metric patterns, it's a user metric
        # regardless of what classification says
        return true if isUserPattern
        
        # Otherwise check classification
        classification = @.resolveLocalClassification(metricId)
        if classification is 'project'
            return false

        if classification is 'team'
            return isUserPattern

        return false
    
    resolveMetricUserContext: (metric) ->
        return null unless metric?

        pickValue = (obj, keys) ->
            return null unless obj?
            for key in keys when obj[key]?
                value = obj[key]
                if typeof value is "string"
                    trimmed = value.trim()
                    return trimmed if trimmed.length
                else if value?
                    return value
            null

        username = pickValue(metric, ["resolvedUsername", "student", "user", "username", "owner"])
        displayName = pickValue(metric, ["resolvedDisplayName", "student_display", "studentDisplay", "user_display", "userDisplay", "displayName"])

        username ?= pickValue(metric.metadata, ["student", "user", "username"])
        displayName ?= pickValue(metric.metadata, ["student_display", "studentDisplay", "user_display", "userDisplay", "displayName"])

        # FIX: Use externalId for username extraction since metric.id from external API is numeric (e.g., 2482)
        # The actual identifier like "commits_claraylv4" is in externalId
        identifierForParsing = metric.externalId or metric.id?.toString()
        if !username and identifierForParsing? and @.isUserMetricId(identifierForParsing)
            parts = identifierForParsing.toString().split("_")
            if parts.length > 1
                username = parts.slice(1).join("_")

        # If we have the metric name (e.g., "Clara Yiní López Vila commits"), extract the display name from it
        if !displayName and metric.name and typeof metric.name is "string"
            # Try to extract the name by removing the metric type suffix
            metricName = metric.name.trim()
            suffixes = [" commits", " closed tasks", " modified lines", " tasks", " assigned tasks"]
            for suffix in suffixes
                if metricName.toLowerCase().endsWith(suffix.toLowerCase())
                    displayName = metricName.substring(0, metricName.length - suffix.length).trim()
                    break

        displayName ?= username

        return null unless username or displayName

        {
            username: username
            displayName: displayName
        }

    buildMetricDisplayGroups: (rawMetrics) ->
        groups =
            project: []
            team: []

        return groups unless angular.isArray(rawMetrics) and rawMetrics.length

        projectBuckets = {}
        teamBuckets = {}
        projectUnassigned = []
        teamUnassigned = []

        pushMetric = (bucket, name, entry) ->
            bucket[name] ?= []
            bucket[name].push(angular.copy(entry))

        for metric in rawMetrics when metric?
            classificationOverride = @.resolveMetricClassificationValue(metric)
            normalizedMetricId = if metric.id? then metric.id.toString().toLowerCase() else null
            normalizedExternalId = if metric.externalId? then metric.externalId.toLowerCase() else null
            
            # Determine if this is a user-specific metric
            # Key insight: if the API explicitly says scope='team', it's NOT a user metric
            # even if the ID pattern looks like one (e.g., commits_sd, commits_anonymous)
            isUserMetric = false
            if metric.scope is 'individual'
                # Explicitly marked as individual -> it's a user metric
                isUserMetric = true
            else if metric.scope is 'team'
                # Explicitly marked as team -> NOT a user metric (aggregate/project metric)
                isUserMetric = false
            else
                # No explicit scope, fallback to pattern matching
                isUserMetric = @.isUserMetricId(normalizedMetricId) or @.isUserMetricId(normalizedExternalId)
            if classificationOverride is 'hidden'
                continue
            
            # Check global configuration classification
            globalHidden = false
            if normalizedMetricId and @metricsConfig.metricClassifications?[normalizedMetricId] is 'hidden'
                globalHidden = true
            if normalizedExternalId and @metricsConfig.metricClassifications?[normalizedExternalId] is 'hidden'
                globalHidden = true
            if globalHidden and classificationOverride not in ['project', 'team']
                continue

            # Determine classification based on configuration
            isProjectConfigured = false
            isTeamConfigured = false

            # Check Project Config
            projectOrderConfig = @localConfig?.projectMetricsOrder
            unless angular.isArray(projectOrderConfig) and projectOrderConfig.length
                projectOrderConfig = @metricsConfig.projectMetricsOrder

            if projectOrderConfig
                for pMetric in projectOrderConfig
                    if @.matchesConfiguredMetric(pMetric, metric.id, metric.externalId, false)
                        isProjectConfigured = true
                        break

            # Check Team Config
            teamOrderConfig = @localConfig?.teamMetricsOrder
            unless angular.isArray(teamOrderConfig) and teamOrderConfig.length
                teamOrderConfig = @metricsConfig.teamMetricsOrder
            
            if teamOrderConfig
                for tMetric in teamOrderConfig
                    matchResult = @.matchesConfiguredMetric(tMetric, metric.id, metric.externalId, true)
                    if matchResult
                        isTeamConfigured = true
                        break
            
            if classificationOverride is 'project'
                isProjectConfigured = true
                isTeamConfigured = false
            else if classificationOverride is 'team'
                isTeamConfigured = true
                isProjectConfigured = false
         
            # [DEBUG AÑADIDO] -> Traza de Gessi / Dashboard para Lidia y Marc
            if normalizedMetricId and (normalizedMetricId.includes("lidix91") or normalizedMetricId.includes("marcoriol"))
                console.log "[DEBUG-TRAZA] #{normalizedMetricId} | isUserMetric: #{isUserMetric} | isTeamConfigured: #{isTeamConfigured} | isProjectConfigured: #{isProjectConfigured} | Provider: #{@metricsProvider}"

            # For external provider: if no classification was resolved, show the metric anyway
            # User metrics go to team view, aggregate metrics go to project view
            if @metricsProvider is "external" and !isProjectConfigured and !isTeamConfigured
                if isUserMetric
                    isTeamConfigured = true
                else
                    # Check if metric looks like a project/aggregate metric
                    isProjectConfigured = true

             if normalizedMetricId and (normalizedMetricId.includes("lidix91") or normalizedMetricId.includes("marcoriol"))
                console.log "[DEBUG-TRAZA-2] #{normalizedMetricId} | POST PROVIDER -> isTeamConfigured: #{isTeamConfigured}"

            # Skip metrics that are not configured for any dashboard slot
            # continue unless isProjectConfigured or isTeamConfigured
            if not isProjectConfigured and not isTeamConfigured
                if normalizedMetricId and (normalizedMetricId.includes("lidix91") or normalizedMetricId.includes("marcoriol"))
                    console.warn "[DEBUG-DROP] Eliminado por NO estar en ProjectConfig ni TeamConfig: #{normalizedMetricId}"
                continue

            # Only keep user-scoped metrics when they are explicitly enabled for the team dashboard
            if isUserMetric and !isTeamConfigured
                if normalizedMetricId and (normalizedMetricId.includes("lidix91") or normalizedMetricId.includes("marcoriol"))
                    console.warn "[DEBUG-DROP] Eliminado por ser UserMetric pero isTeamConfigured es FALSE: #{normalizedMetricId}"
                continue

            normalizedValue = @.normalizeMetricValue(metric.value)
            ratioValue = Math.max(0, Math.min(normalizedValue / 100, 1))
            userContext = @.resolveMetricUserContext(metric)

            # Try to get translated label first, then fallback to backend name
            translatedLabel = @.translateMetricId(metric.id)
            displayLabel = translatedLabel or metric.name or @.formatMetricLabel(metric.id)

            entry =
                id: metric.externalId or metric.id or metric.name
                label: displayLabel
                ratio: ratioValue
                formattedRatio: Number(ratioValue or 0).toFixed(2)
                description: metric.description
                rawValue: normalizedValue
                raw: metric
                user: userContext?.username
                userDisplayName: userContext?.displayName

            # For user metrics, prefer the metric name which typically contains the full user name
            # Example: "Clara Yiní López Vila modified lines" instead of "claraylv4 · Clara..."
            if @.isUserMetricId(entry.id) and userContext?
                # If metric.name exists, use it directly as it already contains the full name
                if metric.name and typeof metric.name is "string" and metric.name.trim().length > 0
                    entry.label = metric.name
                else
                    # Fallback: use displayName if available, otherwise format the metric id
                    displayLabel = userContext.displayName
                    if displayLabel and typeof displayLabel is "string" and displayLabel.trim().length > 0
                        entry.label = displayLabel
                    else
                        entry.label = @.formatMetricLabel(metric.id)

            # Pol Alcoverro added: Resolve colors for gauges
            # For internal user metrics, ALWAYS extract category from ID to group by metric type
            if @metricsProvider is "internal" and isUserMetric and metric.id
                categoryName = @.extractMetricCategoryFromId(metric.id)
                console.log "[DEBUG] Extracted category '#{categoryName}' from user metric ID: #{metric.id}"
            else
                # For non-user metrics, use standard category resolution
                categoryName = metric.categoryName or metric.category_name or metric.category?.name or metric.category
                # If no explicit category name, try to use the first quality factor if available
                if !categoryName and angular.isArray(metric.qualityFactors) and metric.qualityFactors.length > 0
                    categoryName = metric.qualityFactors[0]

            entry.categoryColor = @.resolveMetricCategoryColor(categoryName, normalizedValue)
            entry.categorySegments = @.buildMetricCategorySegments(categoryName)
            entry.categoryName = categoryName
            
            # For internal provider, if no category color was resolved, use value-based color
            # Use ratioValue * 100 to get the percentage for color calculation
            if @metricsProvider is "internal" and not entry.categoryColor
                percentForColor = ratioValue * 100
                entry.categoryColor = @.getInternalGaugeColor(percentForColor, categoryName)
                entry.categoryPalette = @.getInternalGaugePalette(categoryName, metric.id)
                console.log("🎯 Team metric palette:", categoryName, "metricId:", metric.id, entry.categoryPalette)
            
            # For internal provider: if no qualityFactors defined, use extracted category as group
            # Also, if qualityFactors are generic (like "Delivery"), replace with specific category
            effectiveQualityFactors = metric.qualityFactors

            # Fix para el JSON de Gessi: unificar los qualityFactors con las keys del Dashboard
            if angular.isArray(effectiveQualityFactors)
                effectiveQualityFactors = effectiveQualityFactors.map (factor) ->
                    if factor is "commitscontribution" then return "commits"
                    if factor is "modifiedlinescontribution" then return "modifiedlines"
                    return factor
            
            if @metricsProvider is "internal" and (!effectiveQualityFactors or effectiveQualityFactors.length is 0) and categoryName
                effectiveQualityFactors = [categoryName]
            
            if isProjectConfigured
                if angular.isArray(effectiveQualityFactors) and effectiveQualityFactors.length > 0
                    for factorName in effectiveQualityFactors when factorName
                        pushMetric(projectBuckets, factorName, entry)
                else
                    projectUnassigned.push(angular.copy(entry))

            if isTeamConfigured
                if angular.isArray(effectiveQualityFactors) and effectiveQualityFactors.length > 0
                    for factorName in effectiveQualityFactors when factorName
                        pushMetric(teamBuckets, factorName, entry)
                else
                    teamUnassigned.push(angular.copy(entry))

        groups.project = @.convertMetricBucketsToGroups(projectBuckets, projectUnassigned, false)
        groups.team = @.convertMetricBucketsToGroups(teamBuckets, teamUnassigned, true)

        groups

    convertMetricBucketsToGroups: (buckets, unassignedList, isTeam) ->
        result = []

        for own bucketName, metricsList of buckets
            continue unless angular.isArray(metricsList) and metricsList.length > 0
            
            # Define priority for categories to control the order within a group (e.g. user box)
            # Lower number = Higher priority (appears first)
            CATEGORY_PRIORITY =
                'tasks': 10
                'closed_tasks': 20
                'story_points': 30
                'stories_closed': 40
                'commits': 50
                'modified_lines': 60

            # For internal provider and team metrics, group by user first
            if @metricsProvider is "internal" and isTeam
                # Group metrics by user
                userGroups = {}
                for metric in metricsList when metric?
                    userKey = metric.userDisplayName or metric.user or "Unknown User"
                    userGroups[userKey] ?= []
                    userGroups[userKey].push(metric)
                
                # Sort users alphabetically
                sortedUserKeys = Object.keys(userGroups).sort()
                
                # Create a group for each user
                for userKey in sortedUserKeys
                    userMetrics = userGroups[userKey]
                    
                    # Sort metrics within each user group by category priority
                    sortedUserMetrics = userMetrics.slice().sort (a, b) =>
                        aCat = a?.categoryName or @.extractMetricCategoryFromId(a?.id) or ""
                        bCat = b?.categoryName or @.extractMetricCategoryFromId(b?.id) or ""
                        
                        aPriority = CATEGORY_PRIORITY[aCat] or 999
                        bPriority = CATEGORY_PRIORITY[bCat] or 999

                        # First sort by priority
                        priorityCompare = aPriority - bPriority
                        return priorityCompare if priorityCompare isnt 0

                        # Then sort by category name
                        catCompare = aCat.localeCompare(bCat)
                        return catCompare if catCompare isnt 0
                        
                        # Then sort by label
                        aLabel = (a?.label or "").toString().toLowerCase()
                        bLabel = (b?.label or "").toString().toLowerCase()
                        if aLabel < bLabel then -1 else if aLabel > bLabel then 1 else 0
                    
                    result.push({
                        id: "team::#{bucketName}::#{userKey}"
                        name: "#{bucketName}_#{userKey}"
                        label: userKey
                        metrics: sortedUserMetrics
                    })
            else
                # Original behavior for non-internal or non-team metrics
                # Sort metrics: first by category priority, then by label (user name)
                sortedMetrics = metricsList.slice().sort (a, b) =>
                    # Extract category from metric ID for sorting
                    aCat = a?.categoryName or @.extractMetricCategoryFromId(a?.id) or ""
                    bCat = b?.categoryName or @.extractMetricCategoryFromId(b?.id) or ""
                    
                    aPriority = CATEGORY_PRIORITY[aCat] or 999
                    bPriority = CATEGORY_PRIORITY[bCat] or 999

                    # First sort by priority
                    priorityCompare = aPriority - bPriority
                    return priorityCompare if priorityCompare isnt 0

                    # Then sort by category name (if priorities are equal/unknown)
                    catCompare = aCat.localeCompare(bCat)
                    return catCompare if catCompare isnt 0
                    
                    # Then sort by label (usually the metric name)
                    aLabel = (a?.label or "").toString().toLowerCase()
                    bLabel = (b?.label or "").toString().toLowerCase()
                    if aLabel < bLabel then -1 else if aLabel > bLabel then 1 else 0

                label = @.formatMetricCategoryLabel(bucketName)
                result.push({
                    id: "#{if isTeam then 'team' else 'project'}::#{bucketName}"
                    name: bucketName
                    label: label
                    metrics: sortedMetrics
                })

        result.sort (a, b) ->
            aLabel = (a?.label or "").toString().toLowerCase()
            bLabel = (b?.label or "").toString().toLowerCase()
            if aLabel < bLabel then -1 else if aLabel > bLabel then 1 else 0

        if angular.isArray(unassignedList) and unassignedList.length > 0
            # For internal provider and team metrics, also group unassigned by user
            if @metricsProvider is "internal" and isTeam
                # Group unassigned metrics by user
                userGroups = {}
                for metric in unassignedList when metric?
                    userKey = metric.userDisplayName or metric.user or "Unknown User"
                    userGroups[userKey] ?= []
                    userGroups[userKey].push(metric)
                
                # Sort users alphabetically
                sortedUserKeys = Object.keys(userGroups).sort()
                
                # Create a group for each user
                for userKey in sortedUserKeys
                    userMetrics = userGroups[userKey]
                    
                    sortedUserMetrics = userMetrics.slice().sort (a, b) ->
                        aLabel = (a?.label or "").toString().toLowerCase()
                        bLabel = (b?.label or "").toString().toLowerCase()
                        if aLabel < bLabel then -1 else if aLabel > bLabel then 1 else 0
                    
                    result.push({
                        id: "team::uncategorized::#{userKey}"
                        name: "__uncategorized_#{userKey}__"
                        label: userKey
                        metrics: sortedUserMetrics
                    })
            else
                # Original behavior
                sortedFallback = unassignedList.slice().sort (a, b) ->
                    aLabel = (a?.label or "").toString().toLowerCase()
                    bLabel = (b?.label or "").toString().toLowerCase()
                    if aLabel < bLabel then -1 else if aLabel > bLabel then 1 else 0

                label = if @translate?.instant?
                    @translate.instant("METRICS.METRIC_GROUP_UNASSIGNED")
                else
                    "Metrics not associated to any factor"

                result.push({
                    id: "#{if isTeam then 'team' else 'project'}::uncategorized"
                    name: "__uncategorized__"
                    label: label
                    metrics: sortedFallback
                })

        result

    buildProjectMetricEntry: (metric) ->
        return null unless metric

        normalizedValue = @.normalizeMetricValue(metric.value)
        numericValue = if isNaN(normalizedValue) then 0 else normalizedValue
        ratioValue = Math.max(0, numericValue / 100)
        ratioValue = Math.min(1, ratioValue)

        # Use value_description if provided to avoid rounding issues, but keep normalized fallback
        preciseValue = numericValue
        rawDescription = metric.value_description or metric.valueDescription
        if (preciseValue is 0 or !isFinite(preciseValue)) and typeof rawDescription is "string"
            descriptionNumber = parseFloat(rawDescription)
            if typeof descriptionNumber is "number" and !isNaN(descriptionNumber)
                preciseValue = Math.max(0, descriptionNumber * 100)

        roundedValue = Math.round(numericValue)
        formattedPrecise = Number(preciseValue or 0).toFixed(2)

        categoryName = metric.categoryName or metric.category_name or metric.category?.name or metric.category
        # If no explicit category name, try to use the first quality factor if available
        if !categoryName and angular.isArray(metric.qualityFactors) and metric.qualityFactors.length > 0
            rawQualityFactor = metric.qualityFactors[0]
            normalizedQualityFactor = if rawQualityFactor? then rawQualityFactor.toString().toLowerCase() else null

            # Some external metrics come without categoryName but with quality factor ids.
            # Map them to existing visual categories so gauges can render segmented palettes.
            qualityFactorCategoryMap =
                taskeffortinformation: "Deviation"
                taskseffortinformation: "Deviation"

            categoryName = qualityFactorCategoryMap[normalizedQualityFactor] or rawQualityFactor
        
        categoryColor = @.resolveMetricCategoryColor(categoryName, preciseValue or numericValue)
        categorySegments = @.buildMetricCategorySegments(categoryName)
        
        # For internal provider, force palette generation if possible to match Team Metrics style
        categoryPalette = null
        if @metricsProvider is "internal"
            # Use categoryName OR metric ID for palette lookup (mapped in getInternalGaugePalette)
            paletteLookupKey = categoryName or metric.id
            categoryPalette = @.getInternalGaugePalette(paletteLookupKey, metric.id)
            
            # If we have a palette, we might want to ensure color is also set correctly if it was missing
            if !categoryColor and categoryPalette
                percentForColor = ratioValue * 100
                categoryColor = @.getInternalGaugeColor(percentForColor, paletteLookupKey)
        
        # Legacy fallback
        if @metricsProvider is "internal" and not categoryColor
            percentForColor = ratioValue * 100
            categoryColor = @.getInternalGaugeColor(percentForColor, categoryName)

        # Try to get translated name first, then fallback to backend name
        translatedName = @.translateMetricId(metric.id)
        displayName = translatedName or metric.name or metric.id

        return {
            id: metric.id
            name: displayName
            description: metric.description or ""
            value: numericValue
            absoluteValue: numericValue
            displayValueRounded: roundedValue
            displayValuePrecise: formattedPrecise
            absoluteDisplayValueRounded: roundedValue
            absoluteDisplayValuePrecise: formattedPrecise
            ratioValue: ratioValue
            ratioDisplayValueRounded: Math.round(ratioValue * 100) / 100
            ratioDisplayValuePrecise: Number(ratioValue or 0).toFixed(2)
            minLabel: "0%"
            maxLabel: "100%"
            qualityFactor: if angular.isArray(metric.qualityFactors) and metric.qualityFactors.length > 0 then metric.qualityFactors[0] else null
            raw: metric
            categoryName: categoryName
            categoryColor: categoryColor
            categoryPalette: categoryPalette
            categorySegments: categorySegments
        }
    
    scaleProjectMetricsByProjectMax: (metricsArray) ->
        return metricsArray unless angular.isArray(metricsArray) and metricsArray.length > 0

        absoluteValues = []

        for metric in metricsArray when metric?
            absolute = metric.absoluteValue

            if typeof absolute isnt "number" or !isFinite(absolute)
                parsed = parseFloat(absolute)
                absolute = if isNaN(parsed) then null else parsed

            if typeof absolute isnt "number" or !isFinite(absolute)
                fallback = parseFloat(metric?.value)
                absolute = if isNaN(fallback) then null else fallback

            if typeof absolute is "number" and isFinite(absolute) and absolute isnt undefined
                absoluteValues.push(Math.max(0, absolute))

        return metricsArray unless absoluteValues.length

        maxValue = Math.max.apply(Math, absoluteValues)
        return metricsArray unless maxValue > 0

        for metric in metricsArray when metric?
            absolute = metric.absoluteValue

            if typeof absolute isnt "number" or !isFinite(absolute)
                parsed = parseFloat(absolute)
                absolute = if isNaN(parsed) then 0 else parsed

            unless typeof absolute is "number" and isFinite(absolute)
                fallback = parseFloat(metric?.value)
                absolute = if isNaN(fallback) then 0 else fallback

            absolute = Math.max(0, absolute or 0)

            ratio = if maxValue > 0 then absolute / maxValue else 0
            relativePercent = ratio * 100
            relativePercent = Math.max(0, relativePercent)
            relativePercent = Math.round(relativePercent * 100) / 100

            metric.relativePercent = relativePercent
            metric.maxReferenceValue = maxValue
            metric.value = relativePercent
            metric.displayValueRounded = Math.round(relativePercent)
            # Modificado por Pol Alcoverro
            metric.displayValuePrecise = String(Math.round(relativePercent))

        metricsArray
    
    # Prepare pie chart for hours distribution
    prepareHoursPieData: (hoursData) ->
        return null unless hoursData
        
        labels = []
        values = []
        chartColors = []
        borderColors = []

        if typeof hoursData is "object"
            try
                @.registerUserColors(Object.keys(hoursData))
            catch error
                console.warn("Unable to register user colors for hours data:", error)
        
        for student, data of hoursData
            labels.push(student)
            value = if typeof data == 'object' then (data.value || 0) else data
            values.push(value)
            colorPalette = @.resolveUserColor(student)
            solidColor = colorPalette?.solid or colorPalette?.fill or 'rgba(99, 102, 241, 0.7)'
            chartColors.push(solidColor)
            borderColors.push(colorPalette?.border or '#ffffff')
        
        return {
            labels: labels
            values: values
            colors: chartColors
            borderColors: borderColors
        }

    buildStudentsOverallRadar: (usersList) ->
        return null unless usersList and usersList.length > 0

        # Para el proveedor interno usamos métricas que realmente existen (tareas/US)
        if @metricsProvider is "internal"
            return @.buildInternalStudentsRadar(usersList)
        
        assignedLabel = @translate?.instant?("METRICS.RADAR_LABEL_ASSIGNED_TASKS") or "Assigned Tasks"
        commitsLabel = @translate?.instant?("METRICS.RADAR_LABEL_COMMITS") or "Commits"
        modifiedLinesLabel = @translate?.instant?("METRICS.RADAR_LABEL_MODIFIED_LINES") or "Modified Lines"
        
        datasets = []
        @.registerUserColors(usersList)
        
        for user in usersList
            colorPalette = @.resolveUserColor(user)
            borderColor = colorPalette?.border or '#3B82F6'
            areaColor = colorPalette?.fill or 'rgba(59, 130, 246, 0.26)'
            
            assignedTasks = Math.max(0, Math.min(100, parseFloat(user.assignedTasks) or 0))
            commits = Math.max(0, Math.min(100, parseFloat(user.commits) or 0))
            modifiedLines = Math.max(0, Math.min(100, parseFloat(user.modifiedLines) or 0))
            
            dataset = {
                label: "#{user.displayName or user.username}"
                data: [assignedTasks, commits, modifiedLines]
                backgroundColor: areaColor
                borderColor: borderColor
                borderWidth: 2
                pointBackgroundColor: borderColor
                pointBorderColor: '#fff'
                pointHoverBackgroundColor: '#fff'
                pointHoverBorderColor: borderColor
                pointRadius: 4
                pointHoverRadius: 6
            }
            
            datasets.push(dataset)
        
        return {
            labels: [assignedLabel, commitsLabel, modifiedLinesLabel]
            datasets: datasets
        }

    buildInternalStudentsRadar: (usersList) ->
        return null unless usersList and usersList.length > 0

        tasksLabel = @translate?.instant?("METRICS.CLOSED_TASKS_LABEL") or "Closed Tasks"
        storiesLabel = @translate?.instant?("METRICS.RADAR_LABEL_COMPLETED_STORIES") or "Completed Stories"
        workloadLabel = @translate?.instant?("METRICS.RADAR_LABEL_ASSIGNED_TASKS") or "Assigned Tasks"

        datasets = []
        @.registerUserColors(usersList)

        for user in usersList
            colorPalette = @.resolveUserColor(user)
            borderColor = colorPalette?.border or '#3B82F6'
            areaColor = colorPalette?.fill or 'rgba(59, 130, 246, 0.26)'

            tasksVal = Number(parseFloat(user.closedTasks) or 0)
            storiesVal = Number(parseFloat(user.completedUS) or 0)
            workloadCount = Number(parseFloat(user.assignedTasks) or 0)
            
            # Fallback: If completedUS is 0, try to find it in user's metricsDetails
            if storiesVal is 0 and user.metricsDetails?.length > 0
                for metric in user.metricsDetails when metric?.id?
                    if metric.id.toLowerCase().indexOf('completedus') isnt -1
                        rawVal = metric.value or metric.ratio or 0
                        # Normalize if it's a ratio (0-1)
                        if rawVal <= 1 and rawVal > 0
                            storiesVal = rawVal * 100
                        else
                            storiesVal = rawVal
                        console.log "📦 Found completedUS in metricsDetails: #{metric.id} = #{rawVal} -> #{storiesVal}"
                        break
            
            console.log "🎯 Radar data for #{user.username}:", {
                closedTasks: user.closedTasks,
                completedUS: user.completedUS,
                assignedTasks: user.assignedTasks,
                storiesValFinal: storiesVal,
                parsed: [tasksVal, storiesVal, workloadCount]
            }

            datasets.push({
                label: "#{user.displayName or user.username}"
                data: [tasksVal, storiesVal, workloadCount]
                backgroundColor: areaColor
                borderColor: borderColor
                borderWidth: 2
                pointBackgroundColor: borderColor
                pointBorderColor: '#fff'
                pointHoverBackgroundColor: '#fff'
                pointHoverBorderColor: borderColor
                pointRadius: 4
                pointHoverRadius: 6
            })

        {
            labels: [tasksLabel, storiesLabel, workloadLabel]
            datasets: datasets
        }

    buildClosedTasksComparison: (usersList) ->
        return null unless usersList and usersList.length > 0
        
        label = @translate?.instant?("METRICS.CLOSED_TASKS_LABEL") or "Closed Tasks"
        labels = []
        values = []
        barColors = []
        borderColors = []
        
        @.registerUserColors(usersList)

        for user in usersList
            labels.push(user.displayName or user.username)
            closedTasks = Number(parseFloat(user.closedTasks) or parseFloat(user.completedTasks) or 0) or 0
            values.push(Math.max(0, Math.min(100, closedTasks)))
            colorPalette = @.resolveUserColor(user)
            solidColor = colorPalette?.solid or colorPalette?.fill or 'rgba(59, 130, 246, 0.7)'
            barColors.push(solidColor)
            borderColors.push(colorPalette?.border or '#ffffff')
        
        return {
            labels: labels
            datasets: [{
                label: label
                data: values
                backgroundColor: barColors
                borderColor: borderColors
                borderWidth: 1
                borderRadius: 8
                borderSkipped: false
                maxBarThickness: 48
            }]
            options:
                plugins:
                    legend:
                        display: false
        }

    prepareStrategicIndicators: (indicators) ->
        return [] unless angular.isArray(indicators)
        
        processed = []
        
        for indicator in indicators
            continue unless indicator?.id?
            
            # Extract value (can be object with first/second or direct number)
            value = if indicator.value?.first?
                parseFloat(indicator.value.first)
            else if typeof indicator.value is 'number'
                parseFloat(indicator.value)
            else
                0
            
            # Convert to percentage (0-100)
            percentValue = value * 100
            percentValue = Math.max(0, Math.min(100, percentValue))
            
            # Get category label
            categoryLabel = indicator.value?.second or indicator.value_description or ""
            
            entry = {
                id: indicator.id
                name: indicator.name or indicator.id
                description: indicator.description or ""
                value: indicator.value
                displayValue: percentValue
                displayValueRounded: Math.round(percentValue)
                displayValuePrecise: percentValue.toFixed(2)
                categoryLabel: categoryLabel
                date: indicator.date
                rationale: indicator.rationale
                categories_description: indicator.categories_description
            }
            
            processed.push(entry)
        
        return processed

    prepareQualityFactors: (factors) ->
        return [] unless angular.isArray(factors)
        
        processed = []
        
        for factor in factors
            continue unless factor?.id?
            
            # Extract value (can be object with first/second or direct number)
            value = if factor.value?.first?
                parseFloat(factor.value.first)
            else if typeof factor.value is 'number'
                parseFloat(factor.value)
            else
                0
            
            # Convert to percentage (0-100)
            percentValue = value * 100
            percentValue = Math.max(0, Math.min(100, percentValue))
            
            # Assign color and palette based on value for internal provider
            categoryColor = null
            categoryPalette = null
            categoryName = factor.name or factor.id
            if @metricsProvider is "internal"
                categoryColor = @.getInternalGaugeColor(percentValue, categoryName)
                categoryPalette = @.getInternalGaugePalette(categoryName, factor.id)
                console.log("📊 Factor palette assigned:", categoryName, "->", categoryPalette)
            
            entry = {
                id: factor.id
                name: factor.name or factor.id
                description: factor.description or ""
                value: factor.value
                displayValue: percentValue
                displayValueRounded: Math.round(percentValue)
                displayValuePrecise: percentValue.toFixed(2)
                date: factor.date
                type: factor.type
                metrics: factor.metrics or []
                missingMetrics: factor.missingMetrics or []
                categoryColor: categoryColor
                categoryPalette: categoryPalette
            }
            
            processed.push(entry)
        
        return processed
    
    # Returns color for internal gauges based on metric category and percentage value
    # Different colors for different metric types to improve visual organization
    # Generate palette segments for traffic light effect (red-orange-green)
    getInternalGaugePalette: (categoryName = null, metricId = null) ->
        console.log("🎨 getInternalGaugePalette called with:", categoryName, "metricId:", metricId)
        categoryLower = if categoryName then categoryName.toString().toLowerCase() else ""
        metricIdLower = if metricId then metricId.toString().toLowerCase() else ""
        
        # Special case: "Assigned" metrics (tasks/stories ratio per user)
        # Custom ranges: 0-10 Orange, 10-30 Green (ideal), 30-50 Orange, 50-100 Red
        # Backend metric_keys: assignedtasks (Tareas asignadas), totalus (Historias asignadas)
        isAssignedMetric = metricIdLower.indexOf('assignedtasks') isnt -1 or
                           metricIdLower.indexOf('totalus') isnt -1 or
                           metricIdLower.indexOf('assignedus') isnt -1 or
                           metricIdLower.indexOf('tasksratio') isnt -1 or
                           metricIdLower.indexOf('assigned_stories') isnt -1 or
                           metricIdLower.indexOf('assignedstories') isnt -1 or
                           (categoryLower.indexOf('assigned') isnt -1 and categoryLower.indexOf('unassigned') is -1)
        
        if isAssignedMetric
            console.log("🎨 Assigned metric detected, using custom 4-range palette")
            return [
                { value: 10, color: 'rgba(251, 191, 36, 0.9)' }   # 0-10%: Orange
                { value: 20, color: 'rgba(34, 197, 94, 0.9)' }    # 10-30%: Green (ideal)
                { value: 20, color: 'rgba(251, 191, 36, 0.9)' }   # 30-50%: Orange
                { value: 50, color: 'rgba(239, 68, 68, 0.9)' }    # 50-100%: Red
            ]
        
        # Determine if "more is better" or "less is better" for this metric
        higherIsBetter = true
        
        # For unassigned tasks, lower is better (less pending work)
        if categoryLower.indexOf('unassigned') isnt -1
            if categoryLower.indexOf('closed') is -1 and categoryLower.indexOf('completed') is -1
                higherIsBetter = false
        
        palette = if higherIsBetter
            # Green (good) -> Yellow (medium) -> Red (bad)
            [
                { value: 33, color: 'rgba(239, 68, 68, 0.9)' }    # 0-33%: Red
                { value: 33, color: 'rgba(251, 191, 36, 0.9)' }   # 33-66%: Orange/Yellow
                { value: 34, color: 'rgba(34, 197, 94, 0.9)' }    # 66-100%: Green
            ]
        else
            # Red (bad) -> Yellow (medium) -> Green (good)
            [
                { value: 33, color: 'rgba(34, 197, 94, 0.9)' }    # 0-33%: Green
                { value: 33, color: 'rgba(251, 191, 36, 0.9)' }   # 33-66%: Orange/Yellow
                { value: 34, color: 'rgba(239, 68, 68, 0.9)' }    # 66-100%: Red
            ]
        
        console.log("🎨 Returning palette:", palette, "higherIsBetter:", higherIsBetter)
        return palette

    getInternalGaugeColor: (percentValue, categoryName = null) ->
        # If category is provided, use category-specific colors
        if categoryName
            categoryLower = categoryName.toString().toLowerCase()
            
            # Assign colors by metric category for better visual differentiation
            if categoryLower.indexOf('task') isnt -1 or categoryLower.indexOf('tareas') isnt -1
                # Tasks: Blue tones
                if percentValue < 33
                    return 'rgba(239, 68, 68, 0.9)'  # Red
                else if percentValue < 66
                    return 'rgba(59, 130, 246, 0.9)'  # Blue
                else
                    return 'rgba(37, 99, 235, 0.9)'   # Dark Blue
            
            else if categoryLower.indexOf('commit') isnt -1
                # Commits: Purple tones
                if percentValue < 33
                    return 'rgba(239, 68, 68, 0.9)'  # Red
                else if percentValue < 66
                    return 'rgba(168, 85, 247, 0.9)'  # Purple
                else
                    return 'rgba(126, 34, 206, 0.9)'  # Dark Purple
            
            else if categoryLower.indexOf('story') isnt -1 or categoryLower.indexOf('point') isnt -1
                # Story Points: Green tones
                if percentValue < 33
                    return 'rgba(239, 68, 68, 0.9)'  # Red
                else if percentValue < 66
                    return 'rgba(34, 197, 94, 0.9)'   # Green
                else
                    return 'rgba(22, 163, 74, 0.9)'   # Dark Green
            
            else if categoryLower.indexOf('line') isnt -1 or categoryLower.indexOf('code') isnt -1
                # Modified Lines: Orange/Amber tones
                if percentValue < 33
                    return 'rgba(239, 68, 68, 0.9)'  # Red
                else if percentValue < 66
                    return 'rgba(251, 191, 36, 0.9)'  # Amber
                else
                    return 'rgba(245, 158, 11, 0.9)'  # Dark Amber
            
            else if categoryLower.indexOf('hour') isnt -1 or categoryLower.indexOf('time') isnt -1 or categoryLower.indexOf('hora') isnt -1
                # Hours/Time: Teal tones
                if percentValue < 33
                    return 'rgba(239, 68, 68, 0.9)'  # Red
                else if percentValue < 66
                    return 'rgba(20, 184, 166, 0.9)'  # Teal
                else
                    return 'rgba(13, 148, 136, 0.9)'  # Dark Teal
        
        # Default fallback: Red/Orange/Green based on percentage
        if percentValue < 33
            return 'rgba(239, 68, 68, 0.9)'  # Red
        else if percentValue < 66
            return 'rgba(251, 191, 36, 0.9)'  # Orange
        else
            return 'rgba(34, 197, 94, 0.9)'   # Green

    loadInitialData: ->
        @scope.metricsView.loading = true
        
        # Wrap in a promise to handle both synchronous and asynchronous project loading
        return @q.when(@.loadProject())
            .then (project) =>
                return @.fetchProjectConfig()
            .then (config) =>
                @.bootstrapMetricsAccess()
                return config
            .catch (error) =>
                console.error "Metrics: Error in initial data load", error
                @scope.metricsView.loading = false
                @scope.metricsView.error = "METRICS.LOAD_ERROR"
                return @q.reject(error)

    resolveErrorKey: (value, defaultKey) ->
        return defaultKey unless value
        return value if value.indexOf("METRICS.") is 0
        slug = value.replace(/[^a-zA-Z0-9]/g, "_").toUpperCase()
        return "METRICS.ERROR_#{slug}"

    drawTestingCharts: =>
        @.drawRadarChart()
        @.drawSemicircleChart()

    drawRadarChart: ->
        canvas = document.getElementById("radarChart")
        return unless canvas
        
        # Wait for Chart.js to be available
        checkChart = =>
            if window.Chart?
                @.renderRadarWithChartJS(canvas)
            else
                setTimeout(checkChart, 100)
        
        checkChart()
    
    renderRadarWithChartJS: (canvas) ->
        ctx = canvas.getContext("2d")
        return unless ctx
        
        # Destroy existing chart if any
        if @testingRadarChart?
            @testingRadarChart.destroy()
        
        # Data from AMEP11ChopChop real metrics
        data = 
            labels: ["Tasks SD", "Commits SD", "Closed Tasks", "Modified Lines"]
            datasets: [
                {
                    label: 'Development Metrics'
                    data: [7, 19, 83, 0]
                    backgroundColor: 'rgba(52, 152, 219, 0.2)'
                    borderColor: 'rgba(52, 152, 219, 1)'
                    borderWidth: 3
                    pointBackgroundColor: 'rgba(52, 152, 219, 1)'
                    pointBorderColor: '#fff'
                    pointHoverBackgroundColor: '#fff'
                    pointHoverBorderColor: 'rgba(52, 152, 219, 1)'
                    pointRadius: 5
                    pointHoverRadius: 7
                }
            ]
        
        config = 
            type: 'radar'
            data: data
            options:
                responsive: true
                maintainAspectRatio: true
                scales:
                    r:
                        beginAtZero: true
                        min: 0
                        max: 100
                        ticks:
                            stepSize: 20
                            color: '#2c3e50'
                            font:
                                size: 11
                            callback: (value) -> "#{value}%"
                        pointLabels:
                            color: '#2c3e50'
                            font:
                                size: 12
                                weight: 'bold'
                        grid:
                            color: 'rgba(44, 62, 80, 0.15)'
                plugins:
                    legend:
                        display: false
                    tooltip:
                        callbacks:
                            label: (context) ->
                                "#{context.parsed.r}%"
        
        @testingRadarChart = new window.Chart(ctx, config)

    drawSemicircleChart: ->
        canvas = document.getElementById("semicircleChart")
        return unless canvas
        
        # Wait for Chart.js to be available
        checkChart = =>
            if window.Chart?
                @.renderSemicircleWithChartJS(canvas)
            else
                setTimeout(checkChart, 100)
        
        checkChart()
    
    ###
    # Created by: Pol Alcoverro
    # Description: Renders the semicircle gauge that paints the acceptance criteria indicator as a half moon.
    ###
    renderSemicircleWithChartJS: (canvas) ->
        ctx = canvas.getContext("2d")
        return unless ctx
        
        # Destroy existing chart if any
        if @testingSemicircleChart?
            @testingSemicircleChart.destroy()
        
        gaugeContext =
            defaultValue: 11
            data: @scope.metricsView?.data
            project: @scope.project
            scope: @scope

        resolvedValue = @metricsHooks.resolveGaugeValue(gaugeContext)

        if resolvedValue? and !isNaN(parseFloat(resolvedValue))
            value = Number(parseFloat(resolvedValue))
        else if gaugeContext.defaultValue? and !isNaN(parseFloat(gaugeContext.defaultValue))
            value = Number(parseFloat(gaugeContext.defaultValue))
        else
            value = 0
        
        value = Math.max(0, Math.min(100, value or 0))

        # Determine color based on value
        color = if value < 33
            "#f44336"  # Red
        else if value < 66
            "#ff9800"  # Orange
        else
            "#4caf50"  # Green
        
        config = 
            type: 'doughnut'
            data:
                datasets: [
                    {
                        data: [value, 100 - value]
                        backgroundColor: [
                            color
                            'rgba(220, 220, 220, 0.2)'
                        ]
                        borderWidth: 0
                        circumference: 180
                        rotation: 270
                        cutout: '70%'
                        borderRadius: 8
                    }
                ]
            options:
                responsive: true
                maintainAspectRatio: true
                aspectRatio: 2
                plugins:
                    legend:
                        display: false
                    tooltip:
                        enabled: false
            plugins: [
                {
                    id: 'gaugeCenterText'
                    afterDatasetDraw: (chart) =>
                        ctx = chart.ctx
                        width = chart.width
                        height = chart.height
                        
                        # Draw value in center
                        ctx.save()
                        ctx.font = "bold 48px Arial"
                        ctx.fillStyle = "#2c3e50"
                        ctx.textAlign = "center"
                        ctx.textBaseline = "middle"
                        ctx.fillText("#{value}%", width / 2, height / 2 - 20)
                        
                        # Draw label
                        ctx.font = "14px Arial"
                        ctx.fillStyle = "#7f8c8d"
                        ctx.fillText("Strategic Indicators", width / 2, height / 2 + 20)
                        
                        # Draw scale labels
                        ctx.font = "11px Arial"
                        ctx.fillStyle = "#95a5a6"
                        ctx.textAlign = "left"
                        ctx.fillText("0%", 30, height / 2 + 5)
                        ctx.textAlign = "right"
                        ctx.fillText("100%", width - 30, height / 2 + 5)
                        
                        # Draw range labels
                        ctx.font = "bold 10px Arial"
                        ctx.textAlign = "center"
                        
                        ctx.fillStyle = "#f44336"
                        ctx.fillText("Low", width / 2 - 80, height / 2 + 50)
                        
                        ctx.fillStyle = "#ff9800"
                        ctx.fillText("Medium", width / 2, height / 2 + 50)
                        
                        ctx.fillStyle = "#4caf50"
                        ctx.fillText("High", width / 2 + 80, height / 2 + 50)
                        
                        ctx.restore()
                }
            ]
        
        @testingSemicircleChart = new window.Chart(ctx, config)

    ##########################################################################
    # Historical Data Processing Functions
    ##########################################################################
    
    processHistoricalData: (historicalData) ->
        """
        Process historical metrics data from LD backend into chart-ready format
        The LD backend returns data already organized and processed:
        {
            userMetrics: { metricKey: [{date, value, name, username}, ...] },
            projectMetrics: { metricKey: [{date, value, name}, ...] },
            strategicMetrics: { metricKey: [{date, value, name}, ...] },
            qualityFactors: { metricKey: [{date, value, name}, ...] }
        }
        """
        
        # Check if historicalData is the expected object with userMetrics, projectMetrics, etc.
        if !historicalData or typeof historicalData isnt 'object'
            console.warn("No historical data to process or invalid format")
            return {
                userMetrics: {}
                projectMetrics: {}
                strategicMetrics: {}
                qualityFactors: {}
            }
        
        # Extract the raw data from LD backend
        userMetricsRaw = historicalData.userMetrics or {}
        projectMetricsRaw = historicalData.projectMetrics or {}
        strategicMetricsRaw = historicalData.strategicMetrics or {}
        qualityFactorsRaw = historicalData.qualityFactors or {}
        
        # Convert raw data arrays into chart-ready format for tg-area-chart directive
        result = {
            userMetrics: @convertRawMetricsToCharts(userMetricsRaw, 'user')
            projectMetrics: @convertRawMetricsToCharts(projectMetricsRaw, 'project')
            strategicMetrics: @convertRawMetricsToCharts(strategicMetricsRaw, 'strategic')
            qualityFactors: @convertRawMetricsToCharts(qualityFactorsRaw, 'quality')
            raw: historicalData
        }
        
        return result
    
    convertRawMetricsToCharts: (metricsData, category) ->
        """
        Convert raw metrics arrays into Chart.js format for tg-area-chart
        Input: { metricKey: [{date, value, name, student?}, ...], ... }
        Output: { [key]: {labels: [...], datasets: [{...}], ...}, ... }
        """
        result = {}
        
        return result unless metricsData and typeof metricsData is 'object'
        
        for metricKey, dataPoints of metricsData
            continue unless angular.isArray(dataPoints) and dataPoints.length > 0

            # Filter out user metrics from project category
            if category is 'project' and @.isUserMetricId(metricKey) and @.extractHistoricalStudentFromMetricId(metricKey)?
                continue
            
            labels = []
            values = []
            metricName = metricKey
            
            # Extract dates, values, and metric name from data points
            for point in dataPoints when point?
                # Get date/timestamp
                date = point.date or point.timestamp or point.created_at
                labels.push(date) if date
                
                # Get value - handle nested and direct values
                value = 0
                if point.value?
                    if typeof point.value is 'number'
                        value = point.value
                    else if typeof point.value is 'string'
                        parsed = parseFloat(point.value)
                        value = if !isNaN(parsed) then parsed else 0
                    else if typeof point.value is 'object'
                        if point.value.first?
                            value = parseFloat(point.value.first)
                        else if point.value.value?
                            value = if typeof point.value.value is 'number' then point.value.value else parseFloat(point.value.value)
                
                values.push(value)
                
                # Get metric name from first point if available
                if point.name and metricName is metricKey
                    metricName = point.name
            
            # Skip if no valid data
            if labels.length is 0 or values.length is 0
                continue
            
            # Create display label
            displayLabel = if metricName and metricName isnt metricKey
                metricName
            else
                @formatMetricLabel(metricKey)
            
            # Build chart dataset
            maxValue = Math.max.apply(Math, values)

            chartDataset = {
                label: displayLabel
                data: values
                borderColor: '#44C2C2'
                backgroundColor: 'rgba(68, 194, 194, 0.18)'
                fill: true
                tension: 0.3
                borderWidth: 2
                pointRadius: 2.5
                pointHoverRadius: 4
                pointBorderWidth: 1
                pointBackgroundColor: '#44C2C2'
                pointBorderColor: '#ffffff'
            }
            
            # Format as Chart.js structure for tg-area-chart
            result[metricKey] = {
                title: displayLabel
                labels: labels
                datasets: [chartDataset]
                yAxisMax: if maxValue <= 1 then 1.0 else null
                showLegend: false
                metricCategory: category
            }
        
        return result
    
    
    buildTeamHistoricalData: (userMetricsRaw) ->
        result =
            users: []
            chartsByUser: {}
            chartsByCategory: {}

        return result unless userMetricsRaw? and typeof userMetricsRaw is "object"

        # Build comprehensive identity -> displayName map (Taiga, GitHub, metric suffix)
        identityToDisplay = {}
        for rawS in (@scope?.metricsView?.data?.rawStudents or []) when rawS
            dName = rawS.displayName or rawS.name or rawS.username or ""
            continue unless dName.length
            identityToDisplay[rawS.username.toLowerCase()] = dName if rawS.username
            rTaigaU = rawS.identities?.TAIGA?.username
            rGithubU = rawS.identities?.GITHUB?.username
            identityToDisplay[rTaigaU.toLowerCase()] = dName if rTaigaU
            identityToDisplay[rGithubU.toLowerCase()] = dName if rGithubU
            for m in (rawS.metrics or []) when m?
                mId = (m.externalId or m.id or "").toString().toLowerCase()
                if mId.indexOf("_") isnt -1
                    mParts = mId.split("_")
                    if mParts.length >= 2
                        mSuffix = mParts.slice(1).join("_")
                        identityToDisplay[mSuffix] = dName if mSuffix?.length

        # Augment with all known username->displayName mappings from processed users list
        # (includes GitHub usernames resolved via Taiga project member matching)
        for user in (@scope?.metricsView?.data?.usersMetricsList or []) when user?
            uName = user.username or user.displayName or ""
            uDisp = user.displayName or user.name or uName
            identityToDisplay[uName.toLowerCase()] = uDisp if uName and uDisp

        # Augment with suffix->displayName from current metrics auto-discovery (catches unlinked GitHub usernames)
        for own sfx, sfxDisp of (@scope?.metricsView?.data?.suffixToDisplayName or {})
            identityToDisplay[sfx] = sfxDisp if sfx and sfxDisp

        # Augment from rawMetrics (resolved by extractUsersFromMetrics via fuzzy name matching)
        # Maps metric ID suffix -> resolvedDisplayName, catches GitHub usernames not linked in Taiga identities
        for metric in (@scope?.metricsView?.data?.rawMetrics or []) when metric?
            rmId = (metric.externalId or metric.id or "").toString().toLowerCase()
            if rmId.indexOf("_") isnt -1
                rmParts = rmId.split("_")
                if rmParts.length >= 2
                    rmSuffix = rmParts.slice(1).join("_")
                    rmDisp = metric.resolvedDisplayName or metric.userDisplayName
                    identityToDisplay[rmSuffix] = rmDisp if rmSuffix and rmDisp and not identityToDisplay[rmSuffix]

        # Augment with ALL project member username variants (Taiga, GitHub, name combos)
        # This is the most reliable source since it derives from scope.project.members
        for own pmKey, pmEntry of @.getProjectMemberUsernames()
            identityToDisplay[pmKey] = pmEntry.fullName if pmKey and pmEntry?.fullName and not identityToDisplay[pmKey]

        userSet = {}

        mergedMetrics = @.mergeHistoricalMetricSeries(userMetricsRaw)
        console.log "[DEBUG] buildTeamHistoricalData - mergedMetrics keys:", Object.keys(mergedMetrics)

        for own normalizedId, bundle of mergedMetrics
            metricId = bundle?.metricId
            dataPoints = bundle?.dataPoints
            continue unless metricId? and angular.isArray(dataPoints) and dataPoints.length

            category = @.identifyHistoricalMetricCategory(metricId)
            console.log "[DEBUG] metricId:", metricId, "-> category:", category
            continue unless category

            groupedByStudent = {}

            for point in dataPoints when point?
                student = point.student or point.username or point.name or point.user
                continue unless student? and student.toString().trim().length
                nRaw = student.toString().trim().toLowerCase()
                normalizedStudent = identityToDisplay[nRaw] or student.toString().trim()
                groupedByStudent[normalizedStudent] ?= []
                groupedByStudent[normalizedStudent].push(point)

            for student, studentPoints of groupedByStudent
                continue unless angular.isArray(studentPoints) and studentPoints.length

                collection = @.buildHistoricalEntryCollection(student, category, metricId, studentPoints)
                continue unless collection

                userSet[student] = true

                result.chartsByUser[student] ?= {}
                result.chartsByUser[student][category] = collection

                result.chartsByCategory[category] ?= {}
                result.chartsByCategory[category][student] = collection

        result.users = Object.keys(userSet).sort (a, b) ->
            a.localeCompare(b)

        return result

    extractHistoricalStudentFromMetricId: (metricId) ->
        return null unless metricId?

        normalizedId = metricId.toString().toLowerCase()
        parts = normalizedId.split("_")
        return null unless parts.length >= 2

        prefix = parts[0]
        validPrefixes = [
            "assignedtasks"
            "closedtasks"
            "completedtasks"
            "tasksratio"
            "commits"
            "commitscontribution"
            "modifiedlines"
            "modifiedlinescontribution"
            "completedus"
            "totalus"
        ]

        return null unless validPrefixes.indexOf(prefix) isnt -1

        extracted = parts[1..].join("_")
        return null unless extracted?.length
        return null unless @.isValidExternalUsername(extracted)

        extracted

    enrichHistoricalPointsWithStudent: (metricId, dataPoints, onlyIndividual = false) ->
        return [] unless angular.isArray(dataPoints)

        inferredStudent = @.extractHistoricalStudentFromMetricId(metricId)
        enriched = []

        for point in dataPoints when point?
            scope = (point.scope or "").toString().toLowerCase()
            isIndividualScope = scope is "individual"
            includePoint = if onlyIndividual then (isIndividualScope or inferredStudent?) else true
            continue unless includePoint

            cloned = angular.extend({}, point)
            unless cloned.student? or cloned.username? or cloned.user?
                cloned.student = inferredStudent if inferredStudent?
            enriched.push(cloned)

        enriched

    buildTeamHistoricalRawMetrics: (userMetricsRaw, projectMetricsRaw) ->
        merged = {}

        appendSeries = (metricId, points) =>
            return unless metricId? and angular.isArray(points) and points.length
            if merged[metricId]?
                merged[metricId] = merged[metricId].concat(points)
            else
                merged[metricId] = points.slice()

        for own metricId, dataPoints of (userMetricsRaw or {})
            enriched = @.enrichHistoricalPointsWithStudent(metricId, dataPoints, false)
            appendSeries(metricId, enriched)

        for own metricId, dataPoints of (projectMetricsRaw or {})
            enriched = @.enrichHistoricalPointsWithStudent(metricId, dataPoints, true)
            appendSeries(metricId, enriched)

        merged

    buildHistoricalEntryCollection: (student, category, metricId, dataPoints) ->
        return null unless angular.isArray(dataPoints) and dataPoints.length

        entries = []
        metricName = null

        for point in dataPoints when point?
            metricName ?= point.name if point.name?

            rawLabel = point.date or point.timestamp or point.created_at or point.createdAt or point.evaluation_date or point.evaluationDate
            value = @.extractHistoricalPointValue(point)
            continue unless rawLabel? and value?

            timestamp = Date.parse(rawLabel)
            label = if !isNaN(timestamp) then new Date(timestamp).toISOString().slice(0, 10) else rawLabel

            entries.push({
                label: label
                timestamp: if isNaN(timestamp) then null else timestamp
                value: value
                raw: point
            })

        return null unless entries.length

        entries.sort (a, b) ->
            if a.timestamp? and b.timestamp?
                return a.timestamp - b.timestamp
            if a.timestamp? and !b.timestamp?
                return -1
            if !a.timestamp? and b.timestamp?
                return 1
            return a.label.localeCompare(b.label)

        {
            student: student
            category: category
            metricId: metricId
            metricName: metricName
            entries: entries
        }

    normalizeFilterDate: (value) ->
        return null unless value?
        if value instanceof Date
            timestamp = value.getTime()
            return null if isNaN(timestamp)
            return timestamp
        if typeof value is "number" and !isNaN(value)
            return value
        parsed = Date.parse(value)
        return null if isNaN(parsed)
        parsed

    filterHistoricalEntries: (entries, dateFrom, dateTo) ->
        return [] unless angular.isArray(entries)

        fromTimestamp = @.normalizeFilterDate(dateFrom)
        toTimestamp = @.normalizeFilterDate(dateTo)

        return entries unless fromTimestamp? or toTimestamp?

        if toTimestamp?
            # Include the entire to-date day
            toTimestamp += 24 * 60 * 60 * 1000 - 1

        entries.filter (entry) ->
            include = true
            if fromTimestamp? and entry.timestamp?
                include = false if entry.timestamp < fromTimestamp
            if include and toTimestamp? and entry.timestamp?
                include = false if entry.timestamp > toTimestamp
            include

    buildChartDatasetFromEntries: (student, category, entries) ->
        return null unless angular.isArray(entries) and entries.length

        labels = []
        values = []

        for entry in entries
            labels.push(entry.label)
            numericValue = Number(entry.value)
            values.push(if isNaN(numericValue) then 0 else numericValue)

        colorPalette = @.resolveUserColor(student)
        
        # Use category-specific color variations if internal provider
        if @metricsProvider is "internal" and category
            # Calculate average value for color selection
            avgValue = 0
            if values.length > 0
                sum = values.reduce ((a, b) -> a + b), 0
                avgValue = sum / values.length
            
            # Get color based on category and value
            categoryColorRgba = @.getInternalGaugeColor(avgValue, category)
            
            # Parse the rgba to create variations for the chart
            if categoryColorRgba and typeof categoryColorRgba is 'string'
                rgbaMatch = categoryColorRgba.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/)
                if rgbaMatch
                    r = parseInt(rgbaMatch[1])
                    g = parseInt(rgbaMatch[2])
                    b = parseInt(rgbaMatch[3])
                    
                    colorPalette = {
                        border: "rgba(#{r}, #{g}, #{b}, 0.9)"
                        fill: "rgba(#{r}, #{g}, #{b}, 0.26)"
                        solid: "rgba(#{r}, #{g}, #{b}, 0.74)"
                    }

        dataset = {
            label: student
            data: values
            borderColor: colorPalette.border
            backgroundColor: colorPalette.fill
            pointBackgroundColor: colorPalette.border
            pointBorderColor: "#ffffff"
            pointHoverBackgroundColor: colorPalette.border
            pointHoverBorderColor: "#ffffff"
            fill: true
            tension: 0.35
            borderWidth: 2
            pointRadius: 2.5
            pointHoverRadius: 4
            pointBorderWidth: 1
        }

        axisConfig = @.resolveHistoricalAxisConfig(category, values)

        {
            title: student
            labels: labels
            datasets: [dataset]
            showLegend: false
            yAxisMax: axisConfig.max
            yAxisStep: axisConfig.step
            isPercentage: axisConfig.isPercentage
            metricCategory: category
        }

    normalizeHistoricalMetricId: (metricId) ->
        return "" unless metricId?
        metricId.toString().toLowerCase().replace(/[-\s]+/g, "_")

    historicalPointKey: (point) ->
        return null unless point?
        timestamp = @.extractHistoricalPointTimestamp(point)
        if timestamp?
            return "ts::#{timestamp}"

        label = point?.date or point?.label or point?.timestamp or point?.created_at or point?.createdAt
        if label?
            return "label::#{label}"

        try
            return "raw::#{JSON.stringify(point)}"
        catch error
            null

    deduplicateAndSortHistoricalPoints: (points) ->
        return [] unless angular.isArray(points)

        seen = {}
        cleaned = []

        for point in points when point?
            key = @.historicalPointKey(point)
            continue unless key?
            continue if seen[key]
            seen[key] = true
            cleaned.push(point)

        cleaned.sort (a, b) =>
            tsA = @.extractHistoricalPointTimestamp(a)
            tsB = @.extractHistoricalPointTimestamp(b)

            if tsA? and tsB?
                return 0 if tsA is tsB
                return tsA - tsB
            if tsA?
                return -1
            if tsB?
                return 1

            labelA = @.historicalPointKey(a) or ""
            labelB = @.historicalPointKey(b) or ""
            labelA.localeCompare(labelB)

        cleaned

    mergeHistoricalMetricSeries: (metricsRaw) ->
        merged = {}
        return merged unless metricsRaw? and typeof metricsRaw is "object"

        for own metricId, dataPoints of metricsRaw
            continue unless angular.isArray(dataPoints) and dataPoints.length

            normalizedId = @.normalizeHistoricalMetricId(metricId)
            entry = merged[normalizedId]
            pointsCopy = dataPoints.slice()

            if entry?
                entry.dataPoints = entry.dataPoints.concat(pointsCopy)
                entry.sourceIds.push(metricId)
            else
                merged[normalizedId] = {
                    metricId: metricId
                    dataPoints: pointsCopy
                    sourceIds: [metricId]
                }

        for own normalizedId, entry of merged
            entry.dataPoints = @.deduplicateAndSortHistoricalPoints(entry.dataPoints)

        merged

    extractHistoricalPointValue: (point) ->
        return null unless point?

        candidates = [
            point.value
            point.metric_value
            point.metricValue
            point.score
            point.percentage
        ]

        for candidate in candidates when candidate?
            normalized = @.normalizeMetricValue(candidate)
            if typeof normalized is "number" and !isNaN(normalized)
                return normalized

        return null

    extractHistoricalPointTimestamp: (point) ->
        return null unless point?

        raw = point.date or point.timestamp or point.created_at or point.createdAt or point.evaluation_date or point.evaluationDate
        return null unless raw?

        if raw instanceof Date
            timestamp = raw.getTime()
            return null if isNaN(timestamp)
            return timestamp

        if typeof raw is "number" and !isNaN(raw)
            return raw

        parsed = Date.parse(raw)
        return null if isNaN(parsed)
        parsed

    identifyHistoricalMetricCategory: (metricId) ->
        return null unless metricId?

        normalized = metricId.toString().toLowerCase()

        # External data patterns (Learning Dashboard)
        if normalized.indexOf("assignedtasks_") isnt -1 or normalized.indexOf("tasksratio_") isnt -1
            return "tasks"
        if normalized.indexOf("closedtasks_") isnt -1 or normalized.indexOf("completedtasks_") isnt -1
            return "closed_tasks"
        if normalized.indexOf("modifiedlines_") isnt -1 or normalized.indexOf("modifiedlinescontribution_") isnt -1
            return "modified_lines"
        if normalized.indexOf("commits_") isnt -1 or normalized.indexOf("commitscontribution_") isnt -1
            return "commits"
        
        # Internal metrics support (Taiga native) - per user
        if normalized is "user_closed_tasks"
            return "closed_tasks"
        if normalized is "user_story_points"
            return "story_points"
        if normalized is "user_stories_closed"
            return "stories_closed"
        if normalized is "user_commits"
            return "commits"
        if normalized is "user_assigned_tasks"
            return "tasks"
        if normalized is "user_modified_lines"
            return "modified_lines"

        null

    resolveUserColor: (seed) ->
        defaultColor = @userColorPalette?[0] or @.prepareColorFromHex("#6366F1")
        identifier = @.normalizeUserIdentifier(seed)
        return defaultColor unless identifier?.length

        key = @.normalizeUserColorKey(identifier)
        return defaultColor unless key.length

        stored = @userColorAssignments?[key]
        if stored?
            return stored

        aliasKey = @userColorAliasIndex?[key]
        if aliasKey? and @userColorAssignments?[aliasKey]
            return @userColorAssignments[aliasKey]

        similarKey = @.findSimilarUserColorKey(key)
        if similarKey? and @userColorAssignments?[similarKey]
            @userColorAliasIndex ?= {}
            @userColorAliasIndex[key] = similarKey
            return @userColorAssignments[similarKey]

        color = @.assignColorForKey(key)
        color ? defaultColor

    registerUserColors: (users) ->
        return unless users?

        candidates = []

        if angular.isArray(users)
            for user in users when user?
                identifier = @.normalizeUserIdentifier(user)
                continue unless identifier?.length
                key = @.normalizeUserColorKey(identifier)
                continue unless key.length
                candidates.push({
                    identifier: identifier
                    key: key
                    aliases: @.collectUserAliasKeys(user, key)
                })
        else if typeof users is "object"
            for own attr, value of users when value?
                identifier = @.normalizeUserIdentifier(value) or @.normalizeUserIdentifier(attr)
                continue unless identifier?.length
                key = @.normalizeUserColorKey(identifier)
                continue unless key.length
                aliasList = []
                if typeof value is "object" and !angular.isArray(value)
                    aliasList = @.collectUserAliasKeys(value, key)
                else
                    aliasFromAttr = @.normalizeUserColorKey(attr)
                    if aliasFromAttr.length and aliasFromAttr isnt key
                        aliasList.push(aliasFromAttr)
                candidates.push({
                    identifier: identifier
                    key: key
                    aliases: aliasList
                })

        candidates.sort (a, b) ->
            a.identifier.localeCompare(b.identifier)

        seen = {}
        for candidate in candidates
            continue unless candidate?.key
            continue if seen[candidate.key]
            seen[candidate.key] = true
            unless @userColorAssignments?[candidate.key]
                @.assignColorForKey(candidate.key)
            else
                @userColorAliasIndex ?= {}
                @userColorAliasIndex[candidate.key] ?= candidate.key
            @.registerAliasKeys(candidate.aliases, candidate.key)

    resetUserColorAssignments: ->
        @userColorAssignments = {}
        @userColorIndex = 0
        @userColorAliasIndex = {}

    assignColorForKey: (key) ->
        return @userColorAssignments[key] if @userColorAssignments?[key]
        color = @.nextUserColor()
        @userColorAssignments[key] = color
        @userColorAliasIndex ?= {}
        @userColorAliasIndex[key] = key
        color

    nextUserColor: ->
        basePalette = @userColorPalette or []
        if @userColorIndex < basePalette.length
            colorTemplate = basePalette[@userColorIndex]
            @userColorIndex += 1
            if angular?.copy?
                return angular.copy(colorTemplate)
            try
                return JSON.parse(JSON.stringify(colorTemplate))
            catch error
                return colorTemplate

        hue = (@userColorIndex * 47) % 360
        @userColorIndex += 1
        @.generateColorFromHue(hue)

    buildUserColorPalette: ->
        # Pol Alcoverro - Paleta optimizada para equipos de 6-8 personas
        # Los primeros 8 colores están máximamente diferenciados para evitar confusión
        baseHex = [
            "#DC2626"  # 1. Rojo intenso
            "#2563EB"  # 2. Azul rey brillante
            "#059669"  # 3. Verde bosque
            "#F59E0B"  # 4. Ámbar/Naranja cálido
            "#9333EA"  # 5. Púrpura profundo
            "#0891B2"  # 6. Cyan/Turquesa
            "#7C3AED"  # 7. Violeta vivid
            "#65A30D"  # 8. Lima/Verde oliva
            "#6366F1"  # 9. Índigo
            "#F97316"  # 10. Naranja oscuro
            "#14B8A6"  # 11. Teal
            "#A855F7"  # 12. Violeta
            "#EF4444"  # 13. Rojo
            "#0EA5E9"  # 14. Sky blue
            "#22C55E"  # 15. Verde
            "#D946EF"  # 16. Magenta
            "#F43F5E"  # 17. Rosa
            "#3B82F6"  # 18. Azul medio
            "#10B981"  # 19. Verde esmeralda
            "#E53E3E"  # 20. Rojo claro
        ]

        baseHex.map (hex) => @.prepareColorFromHex(hex)

    normalizeUserIdentifier: (input) ->
        return "" unless input?

        if typeof input is "string"
            trimmed = input.toString().trim()
            return trimmed

        if typeof input is "object"
            candidates = [
                input.username
                input.identities?.TAIGA?.username
                input.identities?.GITHUB?.username
                input.displayName
                input.name
                input.fullName
                input.student
                input.user
                input.id
                input.email
            ]

            for candidate in candidates when candidate?
                value = candidate.toString().trim()
                return value if value.length

        ""

    normalizeUserColorKey: (identifier) ->
        return "" unless identifier?
        key = identifier.toString().trim().toLowerCase()
        try
            key = key.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        catch error
            # normalize might not be available; ignore gracefully
            null
        slug = key.replace(/[\s\-]+/g, "_").replace(/[^a-z0-9_]/g, "")
        return slug if slug.length
        key

    collectUserAliasKeys: (user, canonicalKey = "") ->
        aliases = []
        return aliases unless user?

        if typeof user is "object"
            aliasCandidates = [
                user.displayName
                user.name
                user.fullName
                user.student
                user.user
                user.id
                user.email
            ]

            seen = {}
            for candidate in aliasCandidates when candidate?
                aliasKey = @.normalizeUserColorKey(candidate)
                continue unless aliasKey.length
                continue if canonicalKey? and aliasKey is canonicalKey
                continue if seen[aliasKey]
                seen[aliasKey] = true
                aliases.push(aliasKey)
        else if typeof user is "string"
            aliasKey = @.normalizeUserColorKey(user)
            if aliasKey.length and aliasKey isnt canonicalKey
                aliases.push(aliasKey)

        aliases

    registerAliasKeys: (aliases, canonicalKey) ->
        return unless canonicalKey?
        return unless angular.isArray(aliases) and aliases.length

        @userColorAliasIndex ?= {}

        for aliasKey in aliases when aliasKey?
            continue unless aliasKey.length
            continue if aliasKey is canonicalKey
            existing = @userColorAliasIndex[aliasKey]
            if existing? and existing isnt canonicalKey
                continue
            @userColorAliasIndex[aliasKey] = canonicalKey

    findSimilarUserColorKey: (key) ->
        return null unless key?

        assignments = @userColorAssignments or {}

        for own existingKey, color of assignments when existingKey?
            continue unless typeof existingKey is "string"
            if key.indexOf(existingKey) isnt -1 or existingKey.indexOf(key) isnt -1
                return existingKey

        null

    prepareColorFromHex: (hex, fillAlpha = 0.26, solidAlpha = 0.74) ->
        rgb = @.hexToRgb(hex)

        unless rgb?
            return {
                border: hex
                fill: "rgba(99, 102, 241, #{fillAlpha})"
                solid: "rgba(99, 102, 241, #{solidAlpha})"
            }

        {
            border: hex
            fill: "rgba(#{rgb.r}, #{rgb.g}, #{rgb.b}, #{fillAlpha})"
            solid: "rgba(#{rgb.r}, #{rgb.g}, #{rgb.b}, #{solidAlpha})"
        }

    hexToRgb: (hex) ->
        return null unless typeof hex is "string"

        normalized = hex.replace("#", "")
        return null unless normalized.length in [3, 6]

        if normalized.length is 3
            normalized = normalized.split("").map((char) -> "#{char}#{char}").join("")

        intVal = parseInt(normalized, 16)
        return null if isNaN(intVal)

        r = (intVal >> 16) & 255
        g = (intVal >> 8) & 255
        b = intVal & 255

        {r, g, b}

    generateColorFromHue: (hue) ->
        hueValue = ((hue % 360) + 360) % 360
        rgb = @.hslToRgb(hueValue / 360, 0.62, 0.55)
        hex = @.rgbToHex(rgb[0], rgb[1], rgb[2])
        @.prepareColorFromHex(hex)

    hslToRgb: (h, s, l) ->
        h = Math.max(0, Math.min(1, h))
        s = Math.max(0, Math.min(1, s))
        l = Math.max(0, Math.min(1, l))

        if s is 0
            r = l
            g = l
            b = l
        else
            hue2rgb = (p, q, t) ->
                t += 1 if t < 0
                t -= 1 if t > 1
                if t < 1/6
                    return p + (q - p) * 6 * t
                if t < 1/2
                    return q
                if t < 2/3
                    return p + (q - p) * (2/3 - t) * 6
                p

            q = if l < 0.5 then l * (1 + s) else l + s - l * s
            p = 2 * l - q

            r = hue2rgb(p, q, h + 1/3)
            g = hue2rgb(p, q, h)
            b = hue2rgb(p, q, h - 1/3)

        [
            Math.round(r * 255)
            Math.round(g * 255)
            Math.round(b * 255)
        ]

    rgbToHex: (r, g, b) ->
        componentToHex = (value) ->
            clamped = Math.max(0, Math.min(255, Math.round(value)))
            hexComponent = clamped.toString(16)
            if hexComponent.length is 1
                "0#{hexComponent}"
            else
                hexComponent

        "#" + componentToHex(r) + componentToHex(g) + componentToHex(b)

    resolveHistoricalAxisConfig: (category, values) ->
        numericValues = []
        if angular.isArray(values)
            numericValues = values.filter (value) ->
                typeof value is "number" and !isNaN(value)

        maxValue = if numericValues.length then Math.max.apply(Math, numericValues) else 0

        # Only these categories should be treated as percentages (0-100%)
        # closed_tasks is NOT a percentage in internal metrics, but it was in external metrics
        # We need to distinguish or just remove it from here if we want raw counts
        percentageCategories = ["tasks", "modified_lines", "commits"]
        
        isPercentage = percentageCategories.indexOf(category) isnt -1
        
        console.log "[DEBUG] resolveHistoricalAxisConfig - category:", category, "isPercentage:", isPercentage, "maxValue:", maxValue, "percentageCategories:", percentageCategories

        config =
            isPercentage: isPercentage
            max: null
            step: null

        if isPercentage
            baseMax = 100
            adjustedMax = if maxValue > baseMax then Math.ceil(maxValue / 10) * 10 else baseMax
            config.max = adjustedMax
            config.step = 20
        else
            # For non-percentage metrics (counts), set a reasonable max/step
            # If max is small (e.g. < 10), set max to 10 or similar to avoid weird fractional steps
            if maxValue > 0 and maxValue <= 5
                config.max = 5
                config.step = 1
            else if maxValue > 5 and maxValue <= 10
                config.max = 10
                config.step = 2

        return config

    metricCategoryLabelKey: (category) ->
        switch category
            when "tasks" then "METRICS.TEAM_HISTORICAL_METRIC_TASKS"
            when "closed_tasks" then "METRICS.TEAM_HISTORICAL_METRIC_CLOSED_TASKS"
            when "modified_lines" then "METRICS.TEAM_HISTORICAL_METRIC_MODIFIED_LINES"
            when "commits" then "METRICS.TEAM_HISTORICAL_METRIC_COMMITS"
            when "story_points" then "METRICS.TEAM_HISTORICAL_METRIC_STORY_POINTS"
            when "stories_closed" then "METRICS.TEAM_HISTORICAL_METRIC_STORIES_CLOSED"
            else null

    buildQualityFactorNamesMap: (metricsData) ->
        ###
        # Build a map from quality factor id to its display name
        # This allows showing "Modified Lines Contribution" instead of "modifiedlinescontribution"
        # 
        # The API returns data where each item in the main array is a quality factor with:
        # - id: "modifiedlinescontribution"
        # - name: "Modified Lines Contribution"
        # - metrics: [...] (nested individual metrics)
        #
        # Individual metrics have qualityFactors: ["modifiedlinescontribution"] (just the id)
        ###
        map = {}
        return map unless angular.isArray(metricsData)
        
        for item in metricsData when item?.id?
            itemId = item.id.toString().toLowerCase()
            hasName = item.name and typeof item.name is "string" and item.name.trim().length > 0
            
            # An item is a quality factor (parent) if:
            # 1. It has a 'metrics' property (array of child metrics), OR
            # 2. It does NOT have a 'qualityFactors' property (child metrics have this)
            hasMetricsArray = item.hasOwnProperty("metrics")
            hasQualityFactorsArray = angular.isArray(item.qualityFactors) and item.qualityFactors.length > 0
            isQualityFactor = hasMetricsArray or !hasQualityFactorsArray
            
            if hasName and isQualityFactor
                map[itemId] = item.name.trim()
                
            # Also process nested metrics to find any additional quality factor references
            if angular.isArray(item.metrics)
                for childMetric in item.metrics when childMetric?.qualityFactors?
                    # The qualityFactors array contains IDs, and the parent has the name
                    for factorId in childMetric.qualityFactors when factorId
                        normalizedFactorId = factorId.toString().toLowerCase()
                        # If we haven't mapped this factor yet, and the current item is the parent
                        if !map[normalizedFactorId] and itemId is normalizedFactorId and hasName
                            map[normalizedFactorId] = item.name.trim()
        
        return map

    formatMetricCategoryLabel: (category) ->
        return "" unless category?
        categoryStr = category.toString()
        
        # First, check if we have a known name from the quality factors map
        normalizedCategory = categoryStr.toLowerCase()
        
        if @qualityFactorNamesMap? and @qualityFactorNamesMap[normalizedCategory]?
            return @qualityFactorNamesMap[normalizedCategory]
        
        # Known quality factor ID to readable name mappings
        knownQualityFactors = 
            "commitscontribution": "Commits Contribution"
            "commitstasksrelation": "Commits Tasks Relation"
            "commitsmanagement": "Commits Management"
            "fulfillmentoftasks": "Fulfillment of Tasks"
            "fullfillmentoftasks": "Fulfillment of Tasks"  # Typo support
            "taskscontribution": "Tasks Contribution"
            "taskcontribution": "Tasks Contribution"       # Singular support
            "taskseffortinformation": "Tasks Effort Information"
            "taskeffortinformation": "Tasks Effort Information" # Singular support
            "modifiedlinescontribution": "Modified Lines Contribution"
            "userstoriesdefinition_quality": "User Stories Definition Quality"
            "userstoriesdefinitionquality": "User Stories Definition Quality"
            "deviationmetrics": "Deviation Metrics"
            "activitydistribution": "Activity Distribution"
            "unassignedtasks": "Unassigned Tasks"
            "closed_tasks": "Tareas Cerradas"
            "task_completion": "Tareas Cerradas"
            "commits": "Commits"
            "modified_lines": "Líneas Modificadas"
            "tasks": "Tareas Asignadas"
            "story_points": "Puntos de Historia"
            "stories_closed": "Historias Cerradas"
            "tasks_ratio": "Ratio de Tareas"
        
        if knownQualityFactors[normalizedCategory]?
            return knownQualityFactors[normalizedCategory]
        
        # Fallback: Split camelCase and lowercase words, then title case
        # "commitscontribution" -> "Commits Contribution"
        # First try to split by common patterns
        formatted = categoryStr
            # Insert space before uppercase letters (for camelCase)
            .replace(/([a-z])([A-Z])/g, '$1 $2')
            # Split by underscores
            .replace(/_/g, ' ')
            # Split common concatenated words
            .replace(/contribution/gi, ' Contribution')
            .replace(/relation/gi, ' Relation')
            .replace(/management/gi, ' Management')
            .replace(/information/gi, ' Information')
            .replace(/distribution/gi, ' Distribution')
            .replace(/fulfillment/gi, 'Fulfillment ')
            .replace(/deviation/gi, 'Deviation ')
            .replace(/modified/gi, 'Modified ')
            .replace(/quality/gi, ' Quality')
            # Clean up multiple spaces
            .replace(/\s+/g, ' ')
            .trim()
        
        # Title case each word
        words = formatted.split(' ')
        words.map((word) ->
            if word.length > 0
                word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
            else
                word
        ).join(' ')

    composeTeamHistoricalChart: (collection, metricLabelKey, filteredEntries, showUserInTitle = true) ->
        return null unless collection?
        chartData = @.buildChartDatasetFromEntries(collection.student, collection.category, filteredEntries)
        return null unless chartData

        translatedLabel = null
        if metricLabelKey and @translate?.instant?
            translatedLabel = @translate.instant(metricLabelKey)

        baseLabel = @.formatMetricLabel(collection.metricId) or collection.metricName or @.formatMetricCategoryLabel(collection.category)

        metricLabel = translatedLabel or baseLabel

        titleKey = "METRICS.TEAM_HISTORICAL_CARD_TITLE"
        
        if showUserInTitle
            title = if @translate?.instant?
                @translate.instant(titleKey, {metric: metricLabel, user: collection.student})
            else
                "#{metricLabel} · #{collection.student}"
        else
            title = metricLabel

        # Update the chart data title as well, since that's what tg-area-chart uses
        if chartData
            chartData.title = title

        {
            id: "#{collection.category}::#{collection.student}"
            metric: collection.category
            metricLabel: metricLabelKey or metricLabel
            user: collection.student
            title: title
            chartData: chartData
        }

    ###
    # Compose simple charts for internal data - one chart per user per metric
    ###
    composeSimpleTeamHistoricalCharts: (chartsByCategory, dateFrom, dateTo) ->
        charts = []
        unless chartsByCategory?
            console.warn "[WARN] composeSimpleTeamHistoricalCharts - No chartsByCategory provided"
            return charts
        
        console.log "[DEBUG] composeSimpleTeamHistoricalCharts - ENTERED FUNCTION - categories:", Object.keys(chartsByCategory)

        # Para cada métrica y cada usuario, crear un gráfico individual
        for own categoryId, categoryCollections of chartsByCategory
            unless categoryCollections? and typeof categoryCollections is "object"
                console.warn "[WARN] Skipping category #{categoryId} - invalid categoryCollections"
                continue
            
            console.log "[DEBUG] Processing category:", categoryId, "with", Object.keys(categoryCollections).length, "users"

            # Obtener el label de la métrica
            metricLabelKey = @.metricCategoryLabelKey(categoryId)
            
            # Procesar cada usuario individualmente
            for own student, collection of categoryCollections
                continue unless collection?.entries? and angular.isArray(collection.entries)
                
                filteredEntries = @.filterHistoricalEntries(collection.entries, dateFrom, dateTo)
                continue unless angular.isArray(filteredEntries) and filteredEntries.length
                
                # Crear un gráfico para este usuario y esta métrica
                chart = @.composeTeamHistoricalChart(collection, metricLabelKey, filteredEntries, true)
                if chart
                    charts.push(chart)
                    console.log "[DEBUG] Created individual chart for", categoryId, "-", student

        console.log "[DEBUG] composeSimpleTeamHistoricalCharts - created", charts.length, "individual charts"
        
        # Ordenar primero por métrica y luego por usuario para mejor organización
        charts.sort (a, b) ->
            # Primero ordenar por métrica
            labelA = if a?.metricLabel? then a.metricLabel.toString() else ""
            labelB = if b?.metricLabel? then b.metricLabel.toString() else ""
            metricCompare = labelA.localeCompare(labelB)
            return metricCompare if metricCompare isnt 0
            # Si es la misma métrica, ordenar por usuario
            a.user.localeCompare(b.user)

        charts

    composeAggregatedTeamHistoricalCharts: (chartsByCategory, dateFrom, dateTo) ->
        charts = []
        return charts unless chartsByCategory?

        for own categoryId, categoryCollections of chartsByCategory
            chart = @.composeAggregatedTeamHistoricalChart(categoryId, categoryCollections, dateFrom, dateTo)
            charts.push(chart) if chart?

        charts.sort (a, b) ->
            labelA = if a?.metricLabel? then a.metricLabel.toString() else ""
            labelB = if b?.metricLabel? then b.metricLabel.toString() else ""
            labelA.localeCompare(labelB)

        charts

    composeAggregatedTeamHistoricalChart: (categoryId, categoryCollections, dateFrom, dateTo) ->
        return null unless categoryCollections? and typeof categoryCollections is "object"

        try
            @.registerUserColors(Object.keys(categoryCollections))
        catch error
            console.warn("Unable to register colors for aggregated category #{categoryId}:", error)

        datasetInfos = []
        labelSet = {}
        allValues = []

        for own student, collection of categoryCollections
            continue unless collection?.entries? and angular.isArray(collection.entries)

            filteredEntries = @.filterHistoricalEntries(collection.entries, dateFrom, dateTo)
            continue unless angular.isArray(filteredEntries) and filteredEntries.length

            chartData = @.buildChartDatasetFromEntries(collection.student, collection.category, filteredEntries)
            continue unless chartData?

            labels = chartData.labels or []
            dataset = chartData.datasets?[0]
            continue unless angular.isArray(labels) and labels.length and dataset?

            datasetTemplate = angular.copy(dataset) or {}
            valueMap = {}

            for label, idx in labels
                continue unless label?
                value = dataset.data?[idx]
                if typeof value is "number" and !isNaN(value)
                    allValues.push(value)
                    valueMap[label] = value
                else
                    valueMap[label] = null
                labelSet[label] = true

            continue unless Object.keys(valueMap).length

            datasetInfos.push({
                dataset: datasetTemplate
                valueMap: valueMap
                student: collection.student
            })

        labels = Object.keys(labelSet).sort (a, b) ->
            a.localeCompare(b)

        return null unless labels.length and datasetInfos.length

        datasets = []

        for info in datasetInfos
            datasetClone = info.dataset or {}
            datasetClone.data = labels.map (label) ->
                value = info.valueMap[label]
                if typeof value is "number" and !isNaN(value)
                    value
                else if value?
                    numeric = Number(value)
                    if isNaN(numeric)
                        null
                    else
                        numeric
                else
                    null

            datasetClone.fill = false
            datasetClone.label = datasetClone.label or info.student

            hasNumeric = false
            if angular.isArray(datasetClone.data)
                hasNumeric = datasetClone.data.some (value) ->
                    typeof value is "number" and !isNaN(value)

            continue unless hasNumeric

            datasets.push(datasetClone)

        return null unless datasets.length

        axisConfig = @.resolveHistoricalAxisConfig(categoryId, allValues)

        metricLabelKey = @.metricCategoryLabelKey(categoryId)
        translatedLabel = null
        if metricLabelKey and @translate?.instant?
            translatedLabel = @translate.instant(metricLabelKey)

        baseLabel = @.formatMetricCategoryLabel(categoryId)
        metricLabel = translatedLabel or baseLabel

        userLabel = null
        if @translate?.instant?
            userLabel = @translate.instant("METRICS.TEAM_HISTORICAL_ALL_USERS")
        userLabel ?= "All Users"

        titleKey = "METRICS.TEAM_HISTORICAL_CARD_TITLE"
        title = if @translate?.instant?
            @translate.instant(titleKey, {metric: metricLabel, user: userLabel})
        else
            "#{metricLabel} · #{userLabel}"

        chartData =
            title: metricLabel
            labels: labels
            datasets: datasets
            showLegend: datasets.length > 1
            yAxisMax: axisConfig.max
            yAxisStep: axisConfig.step
            isPercentage: axisConfig.isPercentage
            metricCategory: categoryId

        {
            id: "#{categoryId}::all"
            metric: categoryId
            metricLabel: metricLabelKey or metricLabel
            user: userLabel
            title: title
            chartData: chartData
        }

    ###
    # Apply a date preset to the given filters object.
    # Calculates actual from/to dates based on the preset.
    # @param filters {Object} The filters object to modify
    # @param presetId {String} The preset identifier
    ###
    applyDatePreset: (filters, presetId) ->
        return unless filters?
        
        today = new Date()
        toDate = @.formatDateForInput(today)
        fromDate = null
        
        switch presetId
            when "last_7_days"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000))
            when "last_14_days"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 14 * 24 * 60 * 60 * 1000))
            when "last_30_days"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000))
            when "last_90_days"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 90 * 24 * 60 * 60 * 1000))
            when "last_semester"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 180 * 24 * 60 * 60 * 1000))
            when "last_year"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 365 * 24 * 60 * 60 * 1000))
            when "current_month"
                firstOfMonth = new Date(today.getFullYear(), today.getMonth(), 1)
                fromDate = @.formatDateForInput(firstOfMonth)
            when "current_semester"
                # Academic semester: Sep-Jan or Feb-Jul
                month = today.getMonth() + 1  # JS months are 0-indexed
                if month >= 9  # Fall semester (Sep-Jan)
                    fromDate = @.formatDateForInput(new Date(today.getFullYear(), 8, 1))
                else if month >= 2  # Spring semester (Feb-Jul)
                    fromDate = @.formatDateForInput(new Date(today.getFullYear(), 1, 1))
                else  # January (fall semester of previous year)
                    fromDate = @.formatDateForInput(new Date(today.getFullYear() - 1, 8, 1))
            when "all_time"
                fromDate = "2020-01-01"
            else
                # Custom or null - clear preset but keep existing dates
                filters.preset = null
                return
        
        filters.preset = presetId
        filters.dateFrom = fromDate
        filters.dateTo = toDate

    ###
    # Format a Date object to YYYY-MM-DD string for date input
    ###
    formatDateForInput: (date) ->
        return null unless date?
        year = date.getFullYear()
        month = String(date.getMonth() + 1).padStart(2, '0')
        day = String(date.getDate()).padStart(2, '0')
        "#{year}-#{month}-#{day}"

    ###
    # Get human-readable label for the current date range
    ###
    getDateRangeLabel: (filters) ->
        return "" unless filters?
        
        if filters.preset
            presetOption = @scope.metricsView.datePresetOptions?.find (opt) -> opt.id is filters.preset
            if presetOption?.label and @translate?.instant?
                return @translate.instant(presetOption.label)
        
        if filters.dateFrom and filters.dateTo
            return "#{filters.dateFrom} - #{filters.dateTo}"
        else if filters.dateFrom
            return "From #{filters.dateFrom}"
        else if filters.dateTo
            return "Until #{filters.dateTo}"
        
        return ""

    applyTeamHistoricalFilters: ->
        filters = @scope.metricsView.teamHistoricalFilters or {}
        source = @scope.metricsView.teamHistoricalSource
        console.log "[DEBUG] applyTeamHistoricalFilters - source:", source?, "chartsByCategory:", Object.keys(source?.chartsByCategory or {})

        applyOverrides = (chartsList) =>
            context =
                charts: chartsList
                filters: filters
                source: source
                project: @scope.project
                scope: @scope
            transformedCharts = @metricsHooks.transformTeamHistoricalCharts(context)
            if angular.isArray(transformedCharts)
                return transformedCharts
            if angular.isArray(context?.charts)
                return context.charts
            return chartsList

        unless source? and source.chartsByCategory?
            console.log "[DEBUG] applyTeamHistoricalFilters - No source or chartsByCategory, returning empty"
            @scope.metricsView.teamHistoricalCharts = []
            return

        metric = filters.metric or "all"
        user = filters.user or "all"
        dateFrom = filters.dateFrom or null
        dateTo = filters.dateTo or null
        
        # Detectar el proveedor actual - usar la configuración más reciente
        currentProvider = @localConfig?.provider or @scope.config?.provider or @metricsProvider or "external"
        isInternalProvider = currentProvider is "internal"
        console.log "[DEBUG] applyTeamHistoricalFilters - metric:", metric, "user:", user, "provider:", currentProvider, "isInternal:", isInternalProvider

        # Para datos INTERNOS: mostrar gráficos simples por métrica
        # Para datos EXTERNOS: mantener gráficos agregados múltiples
        if user is "all" and metric is "all"
            if isInternalProvider
                # Internal: crear gráficos simples separados por métrica
                simpleCharts = @.composeSimpleTeamHistoricalCharts(source.chartsByCategory, dateFrom, dateTo)
                console.log "[DEBUG] applyTeamHistoricalFilters - simpleCharts (internal):", simpleCharts?.length
                @scope.metricsView.teamHistoricalCharts = applyOverrides(simpleCharts)
            else
                # External: usar gráficos agregados (comportamiento actual)
                aggregatedCharts = @.composeAggregatedTeamHistoricalCharts(source.chartsByCategory, dateFrom, dateTo)
                console.log "[DEBUG] applyTeamHistoricalFilters - aggregatedCharts (external):", aggregatedCharts?.length
                @scope.metricsView.teamHistoricalCharts = applyOverrides(aggregatedCharts)
            return

        metricLabelKey = if metric is "all" then null else @.metricCategoryLabelKey(metric)
        charts = []
        
        # If we are filtering by a specific user, we don't need to show the user name in the title
        showUserInTitle = user is "all"

        processCollection = (collection) =>
            filteredEntries = @.filterHistoricalEntries(collection.entries, dateFrom, dateTo)
            return unless filteredEntries?.length
            chart = @.composeTeamHistoricalChart(collection, metricLabelKey, filteredEntries, showUserInTitle)
            charts.push(chart) if chart

        if user is "all"
            if metric is "all"
                for own categoryId, categoryCollections of source.chartsByCategory
                    for own student, collection of categoryCollections
                        processCollection(collection)
            else
                chartsByCategory = source.chartsByCategory?[metric] or {}
                for own student, collection of chartsByCategory
                    processCollection(collection)
        else
            if metric is "all"
                userCollections = source.chartsByUser?[user] or {}
                for own categoryId, collection of userCollections
                    processCollection(collection)
            else
                collection = source.chartsByUser?[user]?[metric]
                if collection
                    processCollection(collection)

        charts.sort (a, b) ->
            a.user.localeCompare(b.user)

        @scope.metricsView.teamHistoricalCharts = applyOverrides(charts)

    filterProjectHistoricalPoints: (dataPoints, dateFrom, dateTo) ->
        return [] unless angular.isArray(dataPoints)

        fromTimestamp = @.normalizeFilterDate(dateFrom)
        toTimestamp = @.normalizeFilterDate(dateTo)

        return dataPoints.slice() unless fromTimestamp? or toTimestamp?

        if toTimestamp?
            toTimestamp += 24 * 60 * 60 * 1000 - 1

        dataPoints.filter (point) =>
            timestamp = @.extractHistoricalPointTimestamp(point)
            include = true
            if fromTimestamp? and timestamp?
                include = false if timestamp < fromTimestamp
            if include and toTimestamp? and timestamp?
                include = false if timestamp > toTimestamp
            include

    applyProjectHistoricalFilters: (historicalMetrics = null) ->
        historicalMetrics ?= @scope.metricsView.data?.historicalMetrics

        unless historicalMetrics?
            @scope.metricsView.projectHistoricalCharts = []
            return

        filters = @scope.metricsView.projectHistoricalFilters or {}
        rawProjectMetrics = historicalMetrics?.raw?.projectMetrics or {}
        mergedProjectMetrics = @.mergeHistoricalMetricSeries(rawProjectMetrics)
        
        # Update metric options if empty
        if @scope.metricsView.projectHistoricalMetricOptions.length <= 1
            for own metricId, bundle of mergedProjectMetrics
                continue if @.isUserMetricId(metricId) and @.extractHistoricalStudentFromMetricId(metricId)?
                @scope.metricsView.projectHistoricalMetricOptions.push({
                    id: metricId
                    label: bundle.metricLabel or @.formatMetricLabel(metricId)
                })

        filteredData = {}

        applyOverrides = (chartsList, chartMapReference) =>
            context =
                charts: chartsList
                filters: filters
                rawChartMap: chartMapReference
                project: @scope.project
                scope: @scope
            transformedCharts = @metricsHooks.transformProjectHistoricalCharts(context)
            if angular.isArray(transformedCharts)
                return transformedCharts
            if angular.isArray(context?.charts)
                return context.charts
            return chartsList

        for own normalizedId, bundle of mergedProjectMetrics
            # Apply metric filter if not 'all'
            if filters.metric isnt "all" and bundle.metricId isnt filters.metric
                continue

            dataPoints = bundle?.dataPoints
            continue unless angular.isArray(dataPoints) and dataPoints.length

            filteredPoints = @.filterProjectHistoricalPoints(dataPoints, filters.dateFrom, filters.dateTo)
            continue unless filteredPoints.length
            filteredData[bundle.metricId] = filteredPoints

        chartMap = @.convertRawMetricsToCharts(filteredData, 'project')
        charts = []

        # If filtering by specific metric, we can just take it from chartMap
        if filters.metric isnt "all"
            chartData = chartMap[filters.metric]
            if chartData
                charts.push({
                    id: filters.metric
                    title: chartData.title or @.formatMetricLabel(filters.metric)
                    chartData: chartData
                })
        else
            for metricId in @metricsConfig.projectHistoricalMetricsOrder
                chartData = chartMap[metricId]
                continue unless chartData?

                title = chartData.title or @.formatMetricLabel(metricId)
                charts.push({
                    id: metricId
                    title: title
                    chartData: chartData
                })

            for own metricId, chartData of chartMap when @metricsConfig.projectHistoricalMetricsOrder.indexOf(metricId) is -1
                title = chartData.title or @.formatMetricLabel(metricId)
                charts.push({
                    id: metricId
                    title: title
                    chartData: chartData
                })

        @scope.metricsView.projectHistoricalCharts = applyOverrides(charts, chartMap)

    updateTeamHistoricalSource: (historicalMetrics) ->
        console.log "[DEBUG] updateTeamHistoricalSource called, historicalMetrics:", historicalMetrics?
        unless historicalMetrics?
            @scope.metricsView.teamHistoricalSource = null
            @scope.metricsView.teamHistoricalCharts = []
            @.updateProjectHistoricalCharts(null)
            return

        rawUserMetrics = historicalMetrics?.raw?.userMetrics or {}
        rawProjectMetrics = historicalMetrics?.raw?.projectMetrics or {}
        teamHistoricalRaw = @.buildTeamHistoricalRawMetrics(rawUserMetrics, rawProjectMetrics)
        console.log "[DEBUG] rawUserMetrics keys:", Object.keys(rawUserMetrics), "rawProjectMetrics keys:", Object.keys(rawProjectMetrics), "teamHistoricalRaw keys:", Object.keys(teamHistoricalRaw)
        teamData = @.buildTeamHistoricalData(teamHistoricalRaw)
        console.log "[DEBUG] teamData built:", teamData?.users?.length, "users, chartsByCategory:", Object.keys(teamData?.chartsByCategory or {})

        @scope.metricsView.teamHistoricalSource = teamData

        if teamData?.users?.length
            @.registerUserColors(teamData.users)
            @.mergeTeamHistoricalUsers(teamData.users)

        @.applyTeamHistoricalFilters()
        @.updateProjectHistoricalCharts(historicalMetrics)

    updateProjectHistoricalCharts: (historicalMetrics) ->
        if historicalMetrics?
            @.applyProjectHistoricalFilters(historicalMetrics)
        else
            @scope.metricsView.projectHistoricalCharts = []

    buildTeamOverviewDefaultState: ->
        {
            usersList: []
            uiUsers: []
            activeUsers: {}
            activeCount: 0
            baseRadar: null
            baseClosedTasks: null
            filteredRadar: null
            filteredClosedTasks: null
            userLabels: {}
            datasetLabelToUser: {}
            barLabelToUser: {}
        }

    resetTeamOverviewState: ->
        @scope.metricsView.teamOverview = @.buildTeamOverviewDefaultState()

    initializeTeamOverviewState: ->
        @.resetTeamOverviewState()

        data = @scope.metricsView.data
        if !data?
            return

        overview = @scope.metricsView.teamOverview
        overview.baseRadar = angular.copy(data.studentsOverallRadar) or null
        overview.baseClosedTasks = angular.copy(data.studentsClosedTasksBar) or null
        overview.baseTeamMetricGroups = angular.copy(data.teamMetricGroups) or []

        usersList = data?.usersMetricsList
        unless angular.isArray(usersList) and usersList.length > 0
            overview.filteredRadar = angular.copy(overview.baseRadar) or null
            overview.filteredClosedTasks = angular.copy(overview.baseClosedTasks) or null
            overview.activeCount = 0
            return

        overview.usersList = usersList.slice()
        overview.uiUsers = []
        overview.userLabels = {}
        overview.datasetLabelToUser = {}
        overview.barLabelToUser = {}
        overview.activeUsers = {}
        overview.displayNameToUsername = {}  # Reverse mapping: displayName -> username

        for user in usersList when user?
            username = user.username or user.displayName or user.name or user.id
            continue unless username?
            username = username.toString()
            displayName = user.displayName or user.name or username
            overview.userLabels[username] = displayName
            overview.activeUsers[username] = true
            # Also add reverse mapping for display name matching
            overview.displayNameToUsername[displayName] = username

            colorPalette = @.resolveUserColor(user)
            primaryColor = colorPalette?.solid or colorPalette?.fill or "rgba(79, 70, 229, 0.85)"
            borderColor = colorPalette?.border or "#312e81"

            overview.uiUsers.push({
                username: username
                displayName: displayName
                color: primaryColor
                borderColor: borderColor
            })

        if overview.baseRadar?.datasets
            for dataset in overview.baseRadar.datasets when dataset?.label?
                label = dataset.label
                matchedUsername = @.matchUserByLabel(label, overview)
                overview.datasetLabelToUser[label] = matchedUsername if matchedUsername?

        if angular.isArray(overview.baseClosedTasks?.labels)
            for label in overview.baseClosedTasks.labels when label?
                matchedUsername = @.matchUserByLabel(label, overview)
                overview.barLabelToUser[label] = matchedUsername if matchedUsername?

        overview.activeCount = overview.uiUsers.length
        @.updateTeamOverviewCharts()

    updateTeamOverviewCharts: ->
        overview = @scope.metricsView.teamOverview
        return unless overview?

        usersList = overview.usersList or []
        unless angular.isArray(usersList) and usersList.length > 0
            overview.activeCount = 0
            overview.filteredRadar = angular.copy(overview.baseRadar) or null
            overview.filteredClosedTasks = angular.copy(overview.baseClosedTasks) or null
            return

        activeUsernames = []
        for user in usersList when user?
            username = user.username or user.displayName or user.id
            continue unless username?
            username = username.toString()
            isActive = !!overview.activeUsers?[username]
            activeUsernames.push(username) if isActive

        if activeUsernames.length is 0
            for user in usersList when user?.username?
                username = user.username.toString()
                overview.activeUsers[username] = true
                activeUsernames.push(username)

        overview.activeCount = activeUsernames.length

        activeLabels = {}
        for username in activeUsernames
            label = overview.userLabels?[username] or username
            activeLabels[label] = true

        if overview.baseRadar?
            filteredRadar = angular.copy(overview.baseRadar) or {}
            datasets = []
            for dataset in overview.baseRadar?.datasets or []
                label = dataset?.label
                include = false
                if label?
                    username = overview.datasetLabelToUser?[label] or @.matchUserByLabel(label, overview)
                    if username?
                        include = !!overview.activeUsers[username]
                    else
                        include = !!activeLabels[label]
                include = true unless label?
                datasets.push(angular.copy(dataset)) if include
            if datasets.length is 0
                overview.filteredRadar = angular.copy(overview.baseRadar) or null
            else
                filteredRadar.datasets = datasets
                overview.filteredRadar = filteredRadar
        else
            overview.filteredRadar = null

        if overview.baseClosedTasks?
            baseBar = overview.baseClosedTasks
            filteredLabels = []
            selectedIndices = []

            for label, idx in baseBar.labels or []
                include = false
                if label?
                    username = overview.barLabelToUser?[label] or @.matchUserByLabel(label, overview)
                    if username?
                        include = !!overview.activeUsers[username]
                    else
                        include = !!activeLabels[label]
                include = true unless label?
                if include
                    filteredLabels.push(label)
                    selectedIndices.push(idx)

            if filteredLabels.length is 0
                overview.filteredClosedTasks = angular.copy(baseBar) or null
            else
                filteredBar = angular.copy(baseBar) or {}
                filteredBar.labels = filteredLabels
                filteredDatasets = []

                for dataset in baseBar.datasets or []
                    cloned = angular.copy(dataset) or {}
                    if angular.isArray(dataset?.data)
                        cloned.data = selectedIndices.map (index) -> dataset.data[index]
                    if angular.isArray(dataset?.backgroundColor)
                        cloned.backgroundColor = selectedIndices.map (index) -> dataset.backgroundColor[index]
                    if angular.isArray(dataset?.borderColor)
                        cloned.borderColor = selectedIndices.map (index) -> dataset.borderColor[index]
                    if angular.isArray(dataset?.hoverBackgroundColor)
                        cloned.hoverBackgroundColor = selectedIndices.map (index) -> dataset.hoverBackgroundColor[index]
                    filteredDatasets.push(cloned)

                filteredBar.datasets = filteredDatasets
                overview.filteredClosedTasks = filteredBar
        else
            overview.filteredClosedTasks = null

        # Filter Team Metrics Grid
        # Filter Team Metrics Grid
        if overview.baseTeamMetricGroups
            filteredGroups = []
            for group in overview.baseTeamMetricGroups
                filteredMetrics = []
                for metric in group.metrics
                    # Keep metric if it has no user association or if the user is active
                    userKey = metric.user?.toString()
                    displayNameKey = metric.userDisplayName?.toString()
                    
                    # Try to match by username first
                    isActive = !userKey or overview.activeUsers[userKey]
                    
                    # If username didn't match, try to match by displayName
                    if !isActive and displayNameKey and overview.displayNameToUsername
                        mappedUsername = overview.displayNameToUsername[displayNameKey]
                        if mappedUsername and overview.activeUsers[mappedUsername]
                            isActive = true
                    
                    if isActive
                        filteredMetrics.push(metric)
                
                if filteredMetrics.length > 0
                    newGroup = angular.copy(group)
                    newGroup.metrics = filteredMetrics
                    filteredGroups.push(newGroup)
            
            @scope.metricsView.data.teamMetricGroups = filteredGroups

    toggleTeamOverviewUser: (username) ->
        return unless username?

        overview = @scope.metricsView.teamOverview
        return unless overview?.activeUsers?

        normalized = username.toString()
        isActive = !!overview.activeUsers[normalized]

        if isActive and overview.activeCount <= 1
            return

        overview.activeUsers[normalized] = !isActive
        @.updateTeamOverviewCharts()

    resetTeamOverviewUsers: ->
        overview = @scope.metricsView.teamOverview
        return unless overview?

        for user in overview.usersList or []
            username = user?.username or user?.displayName or user?.id
            continue unless username?
            overview.activeUsers[username.toString()] = true

        @.updateTeamOverviewCharts()

    matchUserByLabel: (label, overview = null) ->
        return null unless label?

        labelStr = label.toString()
        return null unless labelStr.length

        overview ?= @scope.metricsView.teamOverview
        return null unless overview?

        username = overview.datasetLabelToUser?[labelStr] or overview.barLabelToUser?[labelStr]
        return username if username?

        for user in overview.uiUsers or [] when user?
            if user.displayName is labelStr or user.username is labelStr
                return user.username

        null

    initializeTeamHistoricalUsers: (usersList) ->
        baseOption = {id: "all", label: "METRICS.TEAM_HISTORICAL_ALL_USERS", translate: true}
        options = [baseOption]
        selectedUser = @scope.metricsView.teamHistoricalFilters?.user

        @.registerUserColors(usersList)

        if angular.isArray(usersList)
            seen = {}
            for user in usersList when user?
                displayName = user.displayName or user.name or user.username or user.id
                continue unless displayName? and displayName.toString().trim().length
                normalized = displayName.toString().trim()
                continue if seen[normalized]
                seen[normalized] = true
                options.push({id: normalized, label: normalized, translate: false})

        hasSelected = false
        if selectedUser?
            hasSelected = options.some (opt) -> opt.id is selectedUser

        @scope.metricsView.teamHistoricalUserOptions = options

        unless hasSelected
            @scope.metricsView.teamHistoricalFilters.user = "all"

    mergeTeamHistoricalUsers: (usernames) ->
        return unless angular.isArray(usernames)

        @.registerUserColors(usernames)

        existing = @scope.metricsView.teamHistoricalUserOptions or []
        options = []
        seen = {}

        for option in existing when option?
            seen[option.id] = true
            options.push(option)

        for username in usernames when username?
            normalized = username.toString().trim()
            continue unless normalized.length
            continue if seen[normalized]
            seen[normalized] = true
            options.push({id: normalized, label: normalized, translate: false})

        options.sort (a, b) ->
            if a.id is "all"
                return -1
            if b.id is "all"
                return 1
            a.label.toString().localeCompare(b.label.toString())

        selectedUser = @scope.metricsView.teamHistoricalFilters?.user
        hasSelected = false
        if selectedUser?
            hasSelected = options.some (opt) -> opt.id is selectedUser

        @scope.metricsView.teamHistoricalUserOptions = options

        unless hasSelected
            @scope.metricsView.teamHistoricalFilters.user = "all"
    
    translateMetricId: (metricId) ->
        """
        Attempt to translate metric ID using METRICS.INTERNAL_METRICS translations.
        Returns the translated label if available, otherwise null.
        """
        return null unless metricId
        return null unless @translate?.instant?

        # Normalize metric ID (remove user suffix if present)
        normalizedId = metricId
        if metricId.indexOf('_') isnt -1
            parts = metricId.split('_')
            # Check if it's a user-scoped metric like "closedtasks_username"
            knownPrefixes = ['closedtasks', 'assignedtasks', 'totalus', 'completedus', 'assignedissues', 'closedissues', 'commits', 'modifiedlines']
            if knownPrefixes.indexOf(parts[0].toLowerCase()) isnt -1
                normalizedId = parts[0].toLowerCase()

        # Try to get translation from METRICS.INTERNAL_METRICS
        translationKey = "METRICS.INTERNAL_METRICS.#{normalizedId}"
        translated = @translate.instant(translationKey)

        # If translation is the same as the key, it means no translation was found
        if translated isnt translationKey
            return translated

        null

    formatMetricLabel: (metricId) ->
        """
        Convert metric ID to a readable label.
        First attempts to use translations, then falls back to static mappings.
        Example: acceptance_criteria_check -> Acceptance Criteria Application
        """
        return metricId unless metricId

        # First, try to use translated label
        translatedLabel = @.translateMetricId(metricId)
        if translatedLabel?
            return translatedLabel

        # Known metric ID to label mappings (fallback for external provider metrics)
        labelMap = {
            'acceptance_criteria_check': 'Acceptance Criteria Application'
            'closed_tasks_with_ae': 'Closed Tasks with Actual Effort Information'
            'commits_anonymous': 'Anonymous Commits'
            'commits_sd': 'Commits Standard Deviation'
            'commits_taskreference': 'Commits Tasks Relation'
            'deviation_effort_estimation_simple': 'Deviation in Estimation of Task Effort'
            'learn_hours': 'Learning hours'
            'pattern_check': 'Use of User Story pattern'
            'tasks_sd': 'Tasks Standard Deviation'
            'tasks_with_ee': 'Tasks with Estimated Effort Information'
            'unassignedtasks': 'Unassigned tasks'
        }

        if labelMap[metricId]
            return labelMap[metricId]

        # Handle user-scoped metrics like "closedtasks_username"
        if metricId.indexOf('_') isnt -1
            parts = metricId.split('_')
            prefix = parts[0]
            userMetricMap = {
                'closedtasks': 'Closed Tasks'
                'completedtasks': 'Closed Tasks'
                'assignedtasks': 'Tasks'
                'tasksratio': 'Tasks'
                'commits': 'Commits'
                'modifiedlines': 'Modified Lines'
                'completedus': 'Completed User Stories'
                'totalus': 'Total User Stories'
            }

            if userMetricMap[prefix]?
                return userMetricMap[prefix]

        # Fallback: Convert snake_case to Title Case
        words = metricId.split('_')
        return words.map((word) ->
            if word.length > 0
                word.charAt(0).toUpperCase() + word.slice(1)
            else
                word
        ).join(' ')

# Filter to check if object has data
module.filter("hasData", -> 
    (obj) ->
        return false unless obj?
        return false unless typeof obj is 'object'
        return Object.keys(obj).length > 0
)

# Register controller
module.controller("MetricsController", MetricsController)
