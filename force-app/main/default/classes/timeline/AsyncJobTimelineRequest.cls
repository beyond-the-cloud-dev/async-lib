/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
public with sharing class AsyncJobTimelineRequest {
    @AuraEnabled
    public Id recordId { get; set; }
    @AuraEnabled
    public Integer daysBack { get; set; }
    @AuraEnabled
    public Integer chainLimit { get; set; }
    @AuraEnabled
    public Integer chainOffset { get; set; }
    @AuraEnabled
    public String statusFilter { get; set; }
    @AuraEnabled
    public List<String> keepChainIds { get; set; }
}
