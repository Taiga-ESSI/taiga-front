###
# Sergio Utrilla added - Instructor Dashboard controllers
# Descripción: Controladores para el dashboard del instructor. InstructorHomeController muestra
#              la lista de subjects y editions; InstructorEditionController muestra el dashboard
#              de una edition concreta con métricas agregadas por grupo.
###

taiga = @.taiga
mixOf = @.taiga.mixOf

module = angular.module("taigaInstructor")


class InstructorHomeController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope"
        "$q"
        "$tgHttp"
        "$tgUrls"
        "tgAppMetaService"
        "$translate"
    ]

    constructor: (@scope, @q, @http, @urls, @appMetaService, @translate) ->
        @translate("INSTRUCTOR.SECTION_NAME").then (name) =>
            @appMetaService.setAll(name, "")

        @scope.view =
            loading: true
            error: null
            subjects: []

        @.load()

    load: ->
        @scope.view.loading = true
        @scope.view.error = null

        subjectsReq = @http.get(@urls.resolve("academics-subjects")).then (r) -> r.data
        editionsReq = @http.get(@urls.resolve("academics-editions")).then (r) -> r.data

        @q.all([subjectsReq, editionsReq]).then ([subjects, editions]) =>
            editionsBySubject = _.groupBy(editions, (e) -> e.subject?.id)
            @scope.view.subjects = subjects.map (s) ->
                s.editions = editionsBySubject[s.id] or []
                s
            @scope.view.loading = false
        .catch (err) =>
            status = err.status or err.statusCode
            if status == 403
                @scope.view.error = "INSTRUCTOR.ACCESS_DENIED"
            else
                @scope.view.error = "INSTRUCTOR.LOAD_ERROR"
            @scope.view.loading = false

module.controller("InstructorHomeController", InstructorHomeController)


class InstructorEditionController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope"
        "$routeParams"
        "$tgHttp"
        "$tgUrls"
        "tgAppMetaService"
        "$translate"
    ]

    constructor: (@scope, @params, @http, @urls, @appMetaService, @translate) ->
        @scope.editionId = parseInt(@params.editionId, 10)

        @scope.view =
            loading: true
            error: null
            edition: null
            groups: []
            aggregated: {}
            refreshing: false

        @scope.refresh = => @.refresh()

        @.load()

    GROUP_COLORS: [
        '#2563EB', '#16A34A', '#DC2626', '#D97706',
        '#7C3AED', '#0891B2', '#DB2777', '#65A30D'
    ]

    load: (force=false) ->
        @scope.view.loading = true
        @scope.view.error = null

        url = @urls.resolve("academics-edition-dashboard", @scope.editionId)
        params = if force then {refresh: "1"} else {}

        return @http.get(url, params).then (response) =>
            data = response.data
            @scope.view.edition =
                id:  data.course_edition_id
                key: data.course_edition_key
            @scope.view.groups     = data.groups or []
            @scope.view.aggregated = data.aggregated or {}
            @scope.view.charts     = @.buildBarCharts(data.aggregated or {})
            @scope.view.loading    = false

            @translate("INSTRUCTOR.EDITION_TITLE", {key: data.course_edition_key}).then (title) =>
                @appMetaService.setAll(title, "")
        .catch (err) =>
            status = err.status or err.statusCode
            if status == 403
                @scope.view.error = "INSTRUCTOR.ACCESS_DENIED"
            else if status == 404
                @scope.view.error = "INSTRUCTOR.EDITION_NOT_FOUND"
            else
                @scope.view.error = "INSTRUCTOR.LOAD_ERROR"
            @scope.view.loading = false

    buildBarCharts: (aggregated) ->
        charts = {}
        for metricId, data of aggregated
            labels = data.values.map (v) -> v.group_code
            values = data.values.map (v) -> v.value
            colors = labels.map (_, i) => @.GROUP_COLORS[i % @.GROUP_COLORS.length]
            charts[metricId] =
                labels: labels
                datasets: [{
                    label: data.metric_name
                    data: values
                    backgroundColor: colors
                    borderColor: colors
                    borderWidth: 1
                }]
        charts

    refresh: ->
        @scope.view.refreshing = true
        @.load(true).finally =>
            @scope.view.refreshing = false

module.controller("InstructorEditionController", InstructorEditionController)


class InstructorGroupController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope"
        "$routeParams"
        "$tgHttp"
        "$tgUrls"
        "tgAppMetaService"
        "$translate"
    ]

    constructor: (@scope, @params, @http, @urls, @appMetaService, @translate) ->
        @scope.editionId = parseInt(@params.editionId, 10)
        @scope.groupId   = parseInt(@params.groupId, 10)

        @scope.view =
            loading: true
            error: null
            edition: null
            group: null
            projectMetrics: []
            students: []
            hasStudents: false
            refreshing: false

        @scope.refresh = => @.refresh()

        @.load()

    load: (force=false) ->
        @scope.view.loading = true
        @scope.view.error = null

        url    = @urls.resolve("academics-edition-dashboard", @scope.editionId)
        params = if force then {refresh: "1"} else {}

        return @http.get(url, params).then (response) =>
            data  = response.data
            group = _.find(data.groups or [], (g) => g.group_id == @scope.groupId)

            unless group
                @scope.view.error   = "INSTRUCTOR.GROUP_NOT_FOUND"
                @scope.view.loading = false
                return

            @scope.view.edition =
                id:  data.course_edition_id
                key: data.course_edition_key

            @scope.view.group          = group
            @scope.view.projectMetrics = (group.metrics or []).filter (m) -> m.classification == 'project'
            @scope.view.students       = group.students or []
            @scope.view.hasStudents    = @scope.view.students.length > 0
            @scope.view.loading        = false

            title = "#{group.group_code} · #{data.course_edition_key}"
            @appMetaService.setAll(title, "")
        .catch (err) =>
            status = err.status or err.statusCode
            if status == 403
                @scope.view.error = "INSTRUCTOR.ACCESS_DENIED"
            else if status == 404
                @scope.view.error = "INSTRUCTOR.EDITION_NOT_FOUND"
            else
                @scope.view.error = "INSTRUCTOR.LOAD_ERROR"
            @scope.view.loading = false

    refresh: ->
        @scope.view.refreshing = true
        @.load(true).finally =>
            @scope.view.refreshing = false

module.controller("InstructorGroupController", InstructorGroupController)
