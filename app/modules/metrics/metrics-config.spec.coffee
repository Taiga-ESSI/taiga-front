###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
# Pol Alcoverro - Tests para el módulo de configuración de métricas
###

describe "tgMetricsConfiguration", ->
    metricsConfig = null

    _inject = ->
        inject (_tgMetricsConfiguration_) ->
            metricsConfig = _tgMetricsConfiguration_

    beforeEach ->
        module "taigaMetrics"
        _inject()

    it "should have default provider set to internal", ->
        provider = metricsConfig.resolveProvider()
        expect(provider).to.be.equal("internal")

    it "should normalize project ids correctly", ->
        normalized = metricsConfig.normalizeId("AMEP11-Beats")
        expect(normalized).to.be.equal("amep11beats")

    it "should normalize project ids removing special characters", ->
        normalized = metricsConfig.normalizeId("Test_Project-123!")
        expect(normalized).to.be.equal("testproject123")

    it "should return empty string for null or undefined ids", ->
        expect(metricsConfig.normalizeId(null)).to.be.equal("")
        expect(metricsConfig.normalizeId(undefined)).to.be.equal("")

    it "should resolve external project id from slug", ->
        externalId = metricsConfig.resolveExternalProjectId("amep11beats")
        expect(externalId).to.be.equal("AMEP11Beats")

    it "should return original slug if not in project id map", ->
        externalId = metricsConfig.resolveExternalProjectId("unknown-project")
        expect(externalId).to.be.equal("unknown-project")

    it "should have default project metrics order", ->
        expect(metricsConfig.projectMetricsOrder).to.be.an("array")
        expect(metricsConfig.projectMetricsOrder).to.include("acceptance_criteria_check")

    it "should have default team metrics order", ->
        expect(metricsConfig.teamMetricsOrder).to.be.an("array")
        expect(metricsConfig.teamMetricsOrder).to.include("assignedtasks")

    it "should have external project ids array", ->
        expect(metricsConfig.externalProjectIds).to.be.an("array")
        expect(metricsConfig.externalProjectIds.length).to.be.above(0)

    it "should build project id map correctly", ->
        expect(metricsConfig.externalProjectIdMap).to.be.an("object")
        expect(metricsConfig.externalProjectIdMap["amep11beats"]).to.be.equal("AMEP11Beats")

    describe "provider resolution", ->
        it "should resolve to internal when provider is internal", ->
            metricsConfig.provider = "internal"
            provider = metricsConfig.resolveProvider()
            expect(provider).to.be.equal("internal")

        it "should resolve to external when provider is external", ->
            metricsConfig.provider = "external"
            provider = metricsConfig.resolveProvider()
            expect(provider).to.be.equal("external")

        it "should default to internal for invalid provider", ->
            metricsConfig.provider = "invalid"
            provider = metricsConfig.resolveProvider()
            expect(provider).to.be.equal("internal")
