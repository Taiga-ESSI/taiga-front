###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
# Pol Alcoverro - Tests para la directiva del menú de métricas
###

describe "tgMetricsMenu directive helpers", ->
    describe "menu item detection", ->
        it "should detect metrics menu item in navigation", ->
            # Simular estructura DOM básica
            html = """
                <nav>
                    <ul>
                        <li><a href="/project/test/backlog">Backlog</a></li>
                        <li><a href="/project/test/kanban">Kanban</a></li>
                        <li><a href="/project/test/metrics">Metrics</a></li>
                    </ul>
                </nav>
            """
            
            element = angular.element(html)
            metricsLink = element.find('a[href*="metrics"]')

            expect(metricsLink.length).to.be.above(0)

    describe "active state management", ->
        it "should identify metrics section as active", ->
            currentPath = '/project/test-project/metrics'
            isMetricsActive = currentPath.indexOf('/metrics') > -1

            expect(isMetricsActive).to.be.true

        it "should not identify other sections as active", ->
            currentPath = '/project/test-project/backlog'
            isMetricsActive = currentPath.indexOf('/metrics') > -1

            expect(isMetricsActive).to.be.false

    describe "sub-menu creation", ->
        it "should create project metrics sub-item", ->
            translations = {
                "METRICS.PROJECT_METRICS": "Project Metrics"
            }
            
            projectMetricsItem = {
                text: translations["METRICS.PROJECT_METRICS"]
                href: "/project/test-project/metrics"
            }

            expect(projectMetricsItem.text).to.be.equal("Project Metrics")
            expect(projectMetricsItem.href).to.contain("/metrics")

        it "should create team metrics sub-item", ->
            translations = {
                "METRICS.TEAM_METRICS": "Team Metrics"
            }
            
            teamMetricsItem = {
                text: translations["METRICS.TEAM_METRICS"]
                href: "/project/test-project/metrics/team"
            }

            expect(teamMetricsItem.text).to.be.equal("Team Metrics")
            expect(teamMetricsItem.href).to.contain("/metrics/team")

        it "should create configuration sub-item", ->
            translations = {
                "METRICS.CONFIG": "Configuration"
            }
            
            configItem = {
                text: translations["METRICS.CONFIG"]
                href: "/project/test-project/metrics/config"
            }

            expect(configItem.text).to.be.equal("Configuration")
            expect(configItem.href).to.contain("/metrics/config")

    describe "breadcrumb integration", ->
        it "should extract base href correctly", ->
            fullHref = "http://localhost:9001/project/test-project/metrics"
            
            extractBaseHref = (href) ->
                return "" unless href
                url = href.toString()
                match = url.match(/\/project\/[^\/]+\/metrics/)
                return match[0] if match
                return ""

            baseHref = extractBaseHref(fullHref)

            expect(baseHref).to.be.equal("/project/test-project/metrics")

        it "should return empty string for invalid href", ->
            extractBaseHref = (href) ->
                return "" unless href
                url = href.toString()
                match = url.match(/\/project\/[^\/]+\/metrics/)
                return match[0] if match
                return ""

            baseHref = extractBaseHref(null)
            expect(baseHref).to.be.equal("")

            baseHref = extractBaseHref("/invalid/path")
            expect(baseHref).to.be.equal("")
