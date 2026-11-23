#Requires -Version 7.6

<#
.SYNOPSIS
    Azure public regions by the names the portal shows.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Data/BlueprintRegionNames.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines values rather than running.
#>

# Azure's public regions by the names the portal shows.
$script:BlueprintRegionName = @{
    eastus = 'East US'; eastus2 = 'East US 2'; centralus = 'Central US'; northcentralus = 'North Central US'
    southcentralus = 'South Central US'; westcentralus = 'West Central US'; westus = 'West US'; westus2 = 'West US 2'
    westus3 = 'West US 3'; canadacentral = 'Canada Central'; canadaeast = 'Canada East'; brazilsouth = 'Brazil South'
    brazilsoutheast = 'Brazil Southeast'; mexicocentral = 'Mexico Central'; chilecentral = 'Chile Central'
    northeurope = 'North Europe'; westeurope = 'West Europe'; uksouth = 'UK South'; ukwest = 'UK West'
    francecentral = 'France Central'; francesouth = 'France South'; germanywestcentral = 'Germany West Central'
    germanynorth = 'Germany North'; switzerlandnorth = 'Switzerland North'; switzerlandwest = 'Switzerland West'
    norwayeast = 'Norway East'; norwaywest = 'Norway West'; swedencentral = 'Sweden Central'; swedensouth = 'Sweden South'
    polandcentral = 'Poland Central'; italynorth = 'Italy North'; spaincentral = 'Spain Central'; austriaeast = 'Austria East'
    belgiumcentral = 'Belgium Central'; denmarkeast = 'Denmark East'; finlandcentral = 'Finland Central'
    greececentral = 'Greece Central'; eastasia = 'East Asia'; southeastasia = 'Southeast Asia'; japaneast = 'Japan East'
    japanwest = 'Japan West'; koreacentral = 'Korea Central'; koreasouth = 'Korea South'; australiaeast = 'Australia East'
    australiasoutheast = 'Australia Southeast'; australiacentral = 'Australia Central'; australiacentral2 = 'Australia Central 2'
    newzealandnorth = 'New Zealand North'; centralindia = 'Central India'; southindia = 'South India'; westindia = 'West India'
    jioindiawest = 'Jio India West'; jioindiacentral = 'Jio India Central'; indonesiacentral = 'Indonesia Central'
    malaysiawest = 'Malaysia West'; taiwannorth = 'Taiwan North'; uaenorth = 'UAE North'; uaecentral = 'UAE Central'
    qatarcentral = 'Qatar Central'; israelcentral = 'Israel Central'; saudiarabiaeast = 'Saudi Arabia East'
    southafricanorth = 'South Africa North'; southafricawest = 'South Africa West'
    usgovvirginia = 'US Gov Virginia'; usgovarizona = 'US Gov Arizona'; usgovtexas = 'US Gov Texas'
    chinanorth = 'China North'; chinaeast = 'China East'; chinanorth2 = 'China North 2'; chinaeast2 = 'China East 2'
    chinanorth3 = 'China North 3'; chinaeast3 = 'China East 3'
}
