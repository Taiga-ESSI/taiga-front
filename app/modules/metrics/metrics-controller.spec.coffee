###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
# Pol Alcoverro - Tests para el controlador de métricas
###

describe "Metrics Module", ->
    $provide = null
    $controller = null
    $scope = null
    mocks = {}

    _mockTgRepo = ->
        mocks.tgRepo = {
            resolve: sinon.stub()
        }
        $provide.value("$tgRepo", mocks.tgRepo)

    _mockTgResources = ->
        mocks.tgResources = {
            projects: {
                getBySlug: sinon.stub()
            }
        }
        $provide.value("$tgResources", mocks.tgResources)

    _mockTgAuth = ->
        mocks.tgAuth = {
            userData: {
                id: 1
                username: "testuser"
            }
        }
        $provide.value("$tgAuth", mocks.tgAuth)

    _mockTgHttp = ->
        mocks.tgHttp = {
            request: sinon.stub()
        }
        $provide.value("$tgHttp", mocks.tgHttp)

    _mockProjectService = ->
        mocks.projectService = {
            project: Immutable.fromJS({
                id: 1
                slug: "test-project"
                name: "Test Project"
                my_permissions: ["view_metrics"]
            })
            setSection: sinon.spy()
            fetchProject: sinon.stub().returns(Promise.resolve())
        }
        $provide.value("tgProjectService", mocks.projectService)

    _mockMetricsConfig = ->
        mocks.metricsConfig = {
            provider: "internal"
            resolveProvider: -> "internal"
            resolveExternalProjectId: (slug) -> slug
            projectMetricsOrder: ["acceptance_criteria_check"]
            teamMetricsOrder: ["assignedtasks"]
        }
        $provide.value("tgMetricsConfiguration", mocks.metricsConfig)

    _mockMetricsCustomization = ->
        mocks.metricsCustomization = {
            getMetricsHooks: -> {}
        }
        $provide.value("tgMetricsCustomization", mocks.metricsCustomization)

    _mockErrorHandlingService = ->
        mocks.errorHandlingService = {
            notfound: sinon.spy()
        }
        $provide.value("tgErrorHandlingService", mocks.errorHandlingService)

    _mockAppMetaService = ->
        mocks.appMetaService = {
            setAll: sinon.spy()
        }
        $provide.value("tgAppMetaService", mocks.appMetaService)

    _mockTranslate = ->
        mocks.translate = {
            instant: (key) -> key
        }
        $provide.value("$translate", mocks.translate)

    _mockNavUrls = ->
        mocks.navUrls = {
            resolve: sinon.stub().returns("/test-url")
        }
        $provide.value("$tgNavUrls", mocks.navUrls)

    _mockUrls = ->
        mocks.urls = {
            resolve: sinon.stub().returns("/test-api-url")
        }
        $provide.value("$tgUrls", mocks.urls)

    _mocks = ->
        module (_$provide_) ->
            $provide = _$provide_

            _mockTgRepo()
            _mockTgResources()
            _mockTgAuth()
            _mockTgHttp()
            _mockProjectService()
            _mockMetricsConfig()
            _mockMetricsCustomization()
            _mockErrorHandlingService()
            _mockAppMetaService()
            _mockTranslate()
            _mockNavUrls()
            _mockUrls()

            return null

    _inject = ->
        inject (_$controller_, _$rootScope_, _$q_, _$location_, _$timeout_) ->
            $controller = _$controller_
            $scope = _$rootScope_.$new()
            mocks.$q = _$q_
            mocks.$location = _$location_
            mocks.$timeout = _$timeout_

    _setup = ->
        _mocks()
        _inject()

    beforeEach ->
        module "taigaMetrics"
        _setup()

    it "should have metrics module loaded", ->
        expect(angular.module("taigaMetrics")).to.exist

    it "should have metrics configuration service", ->
        expect(mocks.metricsConfig).to.exist
        expect(mocks.metricsConfig.provider).to.be.equal("internal")

    it "should have metrics customization service", ->
        expect(mocks.metricsCustomization).to.exist
        expect(mocks.metricsCustomization.getMetricsHooks).to.be.a("function")
