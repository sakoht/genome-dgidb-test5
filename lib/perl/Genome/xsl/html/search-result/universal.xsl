<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:template name="universal_search_result" match="/solr-results/doc">

    <div class="search_result">

    <div>
        <xsl:attribute name="class">
            <xsl:text>result_icon </xsl:text>
            <xsl:value-of select="field[@name='display_icon_url']"/>
        </xsl:attribute>
        <br/>
    </div>

      <div class="result">
        <h3><xsl:value-of select="field[@name='display_type']"/>: 
            <a><xsl:attribute name="href"><xsl:value-of select="field[@name='display_url0']"/></xsl:attribute>
                <xsl:value-of select="field[@name='display_title']"/>
            </a>
        </h3>

        <xsl:if test="field[@name='display_url1']">
            <a class="mini btn">
                <xsl:attribute name="href"><xsl:value-of select="field[@name='display_url1']"/></xsl:attribute>
                <xsl:value-of select="field[@name='display_label1']"/>
            </a>
        </xsl:if>

        <xsl:if test="field[@name='display_url2']">
            <a class="mini btn">
                <xsl:attribute name="href"><xsl:value-of select="field[@name='display_url2']"/></xsl:attribute>
                <xsl:value-of select="field[@name='display_label2']"/>
            </a>
        </xsl:if>

        <xsl:if test="field[@name='display_url3']">
            <a class="mini btn">
                <xsl:attribute name="href"><xsl:value-of select="field[@name='display_url3']"/></xsl:attribute>
                <xsl:value-of select="field[@name='display_label3']"/>
            </a>
        </xsl:if>

        <p class="resource_buttons">

        </p>

        <p class="result_summary">
            <xsl:variable name="id"><xsl:value-of select="field[@name='id']"/></xsl:variable>
            <xsl:value-of disable-output-escaping="yes" select="/solr-results/highlights/highlight_item[@id=$id]/@description"/>
        </p>
      </div>
    </div> <!-- end search_result -->

  </xsl:template>

</xsl:stylesheet>
