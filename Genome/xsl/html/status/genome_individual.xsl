<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:template name="genome_individual" match="object[./types[./isa[@type='Genome::Individual']]]">
    <div class="result">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" class="result"><tbody><tr>
      <td>
        <div class="icon">
           <xsl:call-template name="object_link">
             <xsl:with-param name="linktext">
              <img width="32" height="32" src="/resources/report_resources/apipe_dashboard/images/icons/individual_32.png" />
            </xsl:with-param>
          </xsl:call-template>
        </div>
      </td><td>
        <div class="description">
        <h2 class="name">
          <span class="label">
            Individual:
          </span>
          <span class="title"> 
            <xsl:call-template name="object_link">
              <xsl:with-param name="linktext">
                <xsl:choose>
                  <xsl:when test="normalize-space(aspect[@name='common_name']/value)">
                    <xsl:value-of select="aspect[@name='common_name']/value"/>
                  </xsl:when>
                  <xsl:otherwise>
                    <xsl:value-of select="@id"/>
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:with-param>
            </xsl:call-template>
          </span>
        </h2>
        <p class="info">
          <xsl:value-of select="aspect[@name='name']/value"/> <xsl:value-of select="aspect[@name='gender']/value"/>
        </p>
        <p class="blurb">
          <xsl:value-of select="aspect[@name='description']/value"/>
        </p>
      </div>
      </td></tr></tbody></table>
    </div>
    <xsl:for-each select="aspect[@name='samples']/object">
      <xsl:call-template name="genome_sample"/>
    </xsl:for-each>
  </xsl:template>

</xsl:stylesheet> 