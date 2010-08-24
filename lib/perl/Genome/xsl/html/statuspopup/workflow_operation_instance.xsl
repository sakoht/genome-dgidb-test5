<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:rest="urn:rest">

  <xsl:template name="workflow_operation_instance" match="object[./types[./isa[@type='Workflow::Operation::Instance']]]">

    <xsl:if test="count(ancestor::aspect) = 0">
      <script type='text/javascript' src='/res/js/app/workflow_operation_instance.js'></script>

      <table class="lister" border="0" width="100%" cellspacing="0" cellpadding="0">
        <colgroup>
          <col/>
          <col width="40%"/>
          <col/>
          <col/>
          <col/>
          <col/>
        </colgroup>
        <thead>
          <tr>
            <th>idx</th>
            <th>operation</th>
            <th class="center">status</th>
            <th class="right">start time</th>
            <th class="right">end time</th>
            <th class="right">elapsed</th>
            <th><br/></th>
          </tr>
        </thead>
        <tbody>
          <xsl:call-template name="inner_woi"/>
        </tbody>
      </table>
    </xsl:if>
    <xsl:if test="count(ancestor::aspect) > 0">
      <xsl:call-template name="inner_woi"/>
    </xsl:if>

  </xsl:template>

  <xsl:template name="inner_woi">

    <xsl:if test="count(aspect[@name='operation_type']/object/types/isa[@type='Workflow::OperationType::Command']) + count(aspect[@name='operation_type']/object/types/isa[@type='Workflow::OperationType::Event']) > 0">

      <xsl:variable name="currentLink">
        <xsl:value-of select="rest:typetourl(aspect[@name='current']/object[1]/@type)" />
      </xsl:variable>

      <tr>
        <xsl:for-each select="aspect[@name='parallel_index']">
          <td><xsl:value-of select="value"/></td>
        </xsl:for-each>
        <xsl:for-each select="aspect[@name='name']">
          <td><xsl:value-of select="value"/></td>
        </xsl:for-each>
        <xsl:for-each select="aspect[@name='status']">
          <td class="center"><xsl:attribute name="class"><xsl:text>status </xsl:text><xsl:value-of select="value"/></xsl:attribute><xsl:value-of select="value"/></td>
        </xsl:for-each>
        <xsl:for-each select="aspect[@name='start_time']">
          <td class="right"><xsl:value-of select="value"/></td>
        </xsl:for-each>
        <xsl:for-each select="aspect[@name='end_time']">
          <td class="right"><xsl:value-of select="value"/></td>
        </xsl:for-each>
        <xsl:for-each select="aspect[@name='elapsed_time']">
          <td class="right"><xsl:value-of select="value"/></td>
        </xsl:for-each>
        <td class="buttons">
          <a class="mini btn popup-ajax">
            <xsl:attribute name="href">
              <xsl:text>/view/</xsl:text>
              <xsl:value-of select="$currentLink"/>
              <xsl:text>/statuspopup.html?id=</xsl:text>
              <xsl:value-of select="aspect[@name='current']/object[1]/@id"/>
            </xsl:attribute>
            <xsl:attribute name="title">
              <xsl:value-of select="aspect[@name='name']/value"/>
            </xsl:attribute>
            <span class="sm-icon sm-icon-newwin"><br/></span><xsl:text>info</xsl:text>
          </a>
        </td>
      </tr>
    </xsl:if>

    <xsl:if test="count(aspect[@name='related_instances']) > 0">
      <xsl:for-each select="aspect[@name='related_instances']">
        <xsl:apply-templates/>
      </xsl:for-each>
    </xsl:if>


  </xsl:template>

</xsl:stylesheet>

