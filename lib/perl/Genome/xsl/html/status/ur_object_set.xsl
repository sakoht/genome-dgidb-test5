<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:template name="genome_object_set" match="object[./types[./isa[@type='UR::Object::Set']]]">

    <xsl:call-template name="set_header">
      <xsl:with-param name="display_name" select="'Query Results'" />
    </xsl:call-template>

    <div class="content rounded shadow">
      <div class="container">

        <!--
            <xsl:value-of select="aspect[@name='rule']/object/display_name"/>
        -->
        <p><strong>Query: </strong> <xsl:value-of select="aspect[@name='rule_display']/value" /></p>
        <table width="100%" cellpadding="0" cellspacing="0" border="0" class="lister">
          <thead>
            <xsl:apply-templates select="aspect[@name='members']/object[1]" mode="set_header" />
          </thead>
          <tbody>
            <xsl:for-each select="aspect[@name='members']">
              <xsl:apply-templates mode="set_row" />
            </xsl:for-each>
          </tbody>
        </table>
      </div> <!-- end container -->
    </div> <!-- end content -->

    <xsl:call-template name="footer">
      <xsl:with-param name="footer_text">
        <br/>
      </xsl:with-param>
    </xsl:call-template>

  </xsl:template>

</xsl:stylesheet>
