<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:template name="genome_processingprofile" match="object[./types[./isa[@type='Genome::ProcessingProfile']]]">
    <div class="result">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" class="result"><tbody><tr>
      <td>
        <div class="icon">
          <xsl:call-template name="object_link">
            <xsl:with-param name="linktext">
              <img width="32" height="32" src="/resources/report_resources/apipe_dashboard/images/icons/eye_16.png" />
            </xsl:with-param>
          </xsl:call-template>
        </div>
      </td><td>
        <div class="description">
        <h2 class="name">
          <span class="label">
            Processing Profile:
          </span>
          <span class="title"> 
            <xsl:call-template name="object_link" />
          </span>
        </h2>
        <p class="info">
          <xsl:value-of select="aspect[@name='type_name']/value"/>
        </p>
      </div>
      </td></tr></tbody></table>
    </div>
  </xsl:template>

</xsl:stylesheet>
