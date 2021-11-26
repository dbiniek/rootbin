###########
# Ikea
# Generates backups, downloads backups and restores backups from remote servers.
# https://confluence.endurance.com/display/HGS2/Migrations%3A+Ikea 
# Please submit all bug reports at jira.endurance.com
#
# (C) 2011 - HostGator.com, LLC
###########

import xml.dom.minidom


def xmlToDict(xmlstring):
    '''Convert an XML doc into a Python dictionary.'''
    doc = xml.dom.minidom.parseString(xmlstring)
    removeWhitespaceNodes(doc.documentElement)
    return elementToDict(doc.documentElement)


def elementToDict(parent):
    '''Turns an XML element into a Python dictionary.'''
    child = parent.firstChild
    if (not child):
        return None
    elif (child.nodeType == xml.dom.minidom.Node.TEXT_NODE):
        return child.nodeValue
    
    
    d = {}
    while child is not None:
        if (child.nodeType == xml.dom.minidom.Node.ELEMENT_NODE):
            try:
                d[child.tagName]
            except KeyError:
                d[child.tagName] = []
            d[child.tagName].append(elementToDict(child))
        child = child.nextSibling
    return d


def removeWhitespaceNodes(node, unlink=True):
    '''Remove leading/trailing whitespaces from XML nodes.'''
    remove_list = []
    for child in node.childNodes:
        if child.nodeType == xml.dom.minidom.Node.TEXT_NODE and not child.data.strip():
            remove_list.append(child)
        elif child.hasChildNodes():
            removeWhitespaceNodes(child, unlink)
    for node in remove_list:
        node.parentNode.removeChild(node)
        if unlink:
            node.unlink()
