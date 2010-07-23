<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <!-- full page display for a instrumentdata flowcell -->
  <xsl:template name="genome_instrumentdata_flowcell" match="//flow-cell">
    <!-- currently uses some old styles, include legacy css -->
    <link rel="stylesheet" href="/res/css/legacy.css" type="text/css" media="screen, projection"/>

    <!-- protovis and related -->
    <script type="text/javascript" src="/res/js/pkg/protovis.js"></script>

    <!-- set up lane data and chart -->
    <script type="text/javascript">
      window.indexData = [];

      id = window.indexData;

      <xsl:for-each select="//lane">

        <xsl:variable name="pos" select="position() - 1" />
        id[<xsl:value-of select="$pos"/>] = {};

        id[<xsl:value-of select="$pos"/>].percent = [
        <xsl:for-each select="index">
          <xsl:value-of select="percent"/>,
          </xsl:for-each>];

          id[<xsl:value-of select="$pos"/>].sequence = [
          <xsl:for-each select="index">
            "<xsl:value-of select="sequence"/>",
            </xsl:for-each>];


            id[<xsl:value-of select="$pos"/>].count = [
            <xsl:for-each select="index">
              <xsl:value-of select="count"/>,
              </xsl:for-each>];

      </xsl:for-each>
<xsl:text disable-output-escaping="yes">
      <![CDATA[

// determine max value of index percentages
// so that all charts have the same x scale

window.pMax = 0;
for (var i=0,len=id.length;i<len;i++) {
for (j in id[i].percent) {
if (id[i].percent[j] > window.pMax) {
window.pMax = id[i].percent[j];
}
}
}

window.chartMax = Math.ceil(window.pMax);
window.chartMin = 0;

console.log("window.chartMax: " + window.chartMax);

      ]]>
</xsl:text>
    </script>

    <style type="text/css">
      div.lane_chart {
      width: 200px;
      float: left;
      margin-left: 15px;
      margin-right: 15px;
      }

      div.legend_block {
      width: 910px;
      float: left;
      background: #EFEFEF;
      padding: 5px;
      }

      div.legend_block div.label {
      font-weight: bold;
      float: left;
      width: 50px;
      }

      div.legend_block div.legend {
      float: left;
      width: 800px;
      background: #CCF;
      }

      div.charts_block {
      float: left;
      width: 920px;
      margin-bottom: 20px;
      }

      p.axis_label_x {
      text-align: center;
      color: #AAA;
      font-size: 11px;
      }

    </style>


    <xsl:call-template name="view_header">
      <xsl:with-param name="label_name" select="'Flow Cell'" />
      <xsl:with-param name="display_name" select="//flow-cell/@id" />
      <xsl:with-param name="icon" select="'genome_instrumentdata_flowcell_32'" />
    </xsl:call-template>

    <div class="content rounded shadow">
      <div class="container">

        <table cellpadding="0" cellspacing="0" border="0" class="info_table_group">
          <tr>
            <td>
              <table border="0" cellpadding="0" cellspacing="0" class="info_table" width="100%">
                <colgroup>
                  <col/>
                  <col width="100%"/>
                </colgroup>
                <tr><td class="label">Flow Cell ID:</td><td class="value"><xsl:value-of select="//flow-cell/@id"/></td></tr>

                <tr><td class="label">Run Type:</td><td class="value"><xsl:value-of select="//production/@run-type"/></td></tr>
                <tr><td class="label">Machine:</td><td class="value"><xsl:value-of select="//production/@machine-name"/></td></tr>
              </table>
            </td>
            <td>
              <table border="0" cellpadding="0" cellspacing="0" class="info_table" width="100%">
                <colgroup>
                  <col/>
                  <col width="100%"/>
                </colgroup>
                <tr><td class="label">Run Name:</td><td class="value"><xsl:value-of select="//production/@run-name"/></td></tr>
                <tr><td class="label">Date Started:</td><td class="value"><xsl:value-of select="//production/@date-started"/></td></tr>
                <tr><td class="label">Group:</td><td class="value"><xsl:value-of select="//production/@group-name"/></td></tr>
              </table>
            </td>
          </tr>
        </table>
        <hr/>

        <h2>lanes</h2>
        <table id="lane_list" class="list tablesorter" width="100%" cellspacing="0" cellpadding="0" border="0">
          <colgroup>
            <col />
            <col />
          </colgroup>
          <thead>
            <tr>
              <th>lane</th>
              <th>id</th>
              <th>reports</th>
              <th>resources</th>
            </tr>
          </thead>
          <tbody>
            <xsl:choose>
              <xsl:when test="count(//instrument-data) > 0">
                <xsl:for-each select="//instrument-data">
                  <xsl:sort select="@subset_name" data-type="text" order="ascending"/>
                  <xsl:variable name="build-status" select="build_status"/>
                  <tr>
                    <td>
                      <xsl:value-of select="@subset_name"/>
                    </td>
                    <td><xsl:value-of select="@id"/></td>
                    <td>
                      <xsl:choose>
                        <xsl:when test="report">
                          <xsl:for-each select="report">
                            <xsl:variable select="@name" name="report_name_full"/>
                            <a><xsl:attribute name="class">btn_link</xsl:attribute><xsl:attribute name="href">/cgi-bin/dashboard/flow_cell_report.cgi?instrument-data-id=<xsl:value-of select="../@id"/>&amp;report-name=<xsl:value-of select="@name"/></xsl:attribute><xsl:value-of select="substring-before($report_name_full,'.')"/></a><xsl:text> </xsl:text>
                          </xsl:for-each>
                        </xsl:when>
                        <xsl:otherwise>
                          <span class="note">No reports available for this lane.</span>
                        </xsl:otherwise>
                      </xsl:choose>
                    </td>
                    <td>
                      <xsl:choose>
                        <xsl:when test="@gerald-directory">
                          <a><xsl:attribute name="class">btn_link</xsl:attribute><xsl:attribute name="href">https://gscweb<xsl:value-of select="@gerald-directory"/></xsl:attribute>gerald directory</a>
                        </xsl:when>
                        <xsl:otherwise>
                          <span class="note">No resources found.</span>
                        </xsl:otherwise>
                      </xsl:choose>
                    </td>
                  </tr>
                </xsl:for-each>
              </xsl:when>
              <xsl:otherwise>
                <tr>
                  <td colspan="5">
                    <strong>No available lanes for this flow cell.</strong>
                  </td>
                </tr>
              </xsl:otherwise>
            </xsl:choose>
          </tbody>
        </table>
        <xsl:if test="/flow-cell/illumina-lane-index">
          <h2 style="border-bottom: 2px solid #CCC;">Lane index report</h2>

          <div class="charts_block">
            <xsl:for-each select="//report">
              <xsl:apply-templates select="lane" />
            </xsl:for-each>
          </div>

        </xsl:if>

      </div> <!-- end container -->
    </div> <!-- end content -->

    <xsl:call-template name="footer">
      <xsl:with-param name="footer_text">
        <br/>
      </xsl:with-param>
    </xsl:call-template>


  </xsl:template>

  <xsl:template match="lane">
    <div class="lane_chart">
      <h3>Lane <xsl:value-of select="@number"/></h3>

      <script type="text/javascript+protovis">
        <xsl:text disable-output-escaping="yes">
        console.log("executing lane index chart.");
        var y_bars = window.indexData[0].sequence.length,
        w = 150,
        h = y_bars * 15,
        x = pv.Scale.linear(window.chartMin, window.chartMax).range(0, w),
        y = pv.Scale.ordinal(pv.range(y_bars)).splitBanded(0, h, 4/5),
        c = pv.Colors.category10();

        var vis =new pv.Panel()
        .width(w)
        .height(h)
        .bottom(20)
        .left(50)
        .right(10)
        .top(5);

        var bar = vis.add(pv.Bar)
        .data(window.indexData[</xsl:text><xsl:value-of select="@number  - 1"/>]<xsl:text disable-output-escaping="yes">.percent)
        .top(function() y(this.index))
        .height(y.range().band)
        .left(0)
        .width(x)
        .fillStyle(function(d) c(window.indexData[</xsl:text><xsl:value-of select="@number  - 1"/>]<xsl:text disable-output-escaping="yes">.sequence[this.index]))
        .title(function() {return "count: " +  addCommas(window.indexData[</xsl:text><xsl:value-of select="@number  - 1"/><xsl:text disable-output-escaping="yes">].count[this.index]) + " index %: " + window.indexData[</xsl:text><xsl:value-of select="@number  - 1"/><xsl:text disable-output-escaping="yes">].percent[this.index] + '%'});

        bar.anchor("right").add(pv.Label)
        .textStyle("white")
        .text(function(d) d.toFixed(2));

        bar.anchor("left").add(pv.Label)
        .textMargin(5)
        .textAlign("right")
        .text(function() window.indexData[</xsl:text><xsl:value-of select="@number  - 1"/><xsl:text disable-output-escaping="yes">].sequence[this.index]);

        vis.add(pv.Rule)
        .data(x.ticks())
        .left(function(d) Math.round(x(d)) - .5)
        .strokeStyle(function(d) d ? "rgba(255,255,255,.3)" : "#999")
        .add(pv.Rule)
        .bottom(0)
        .height(5)
        .strokeStyle("#999")
        .anchor("bottom").add(pv.Label)
        .text(function(d) d.toFixed(1))
        .textStyle("#999");

        vis.render();

        function addCommas(nStr) {
        nStr += '';
        var x = nStr.split('.');
        var x1 = x[0];
        var x2 = x.length > 1 ? '.' + x[1] : '';
        var rgx = /(\d+)(\d{3})/;
        while (rgx.test(x1)) {
        x1 = x1.replace(rgx, '$1' + ',' + '$2');
        }
        return x1 + x2;
        }
      </xsl:text>
      </script>
      <p class="axis_label_x">Index %</p>
    </div>

  </xsl:template>
</xsl:stylesheet>
