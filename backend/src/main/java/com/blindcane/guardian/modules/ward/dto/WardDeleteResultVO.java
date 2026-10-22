package com.blindcane.guardian.modules.ward.dto;

/**
 * 删除档案的连带清理结果。
 *
 * <p>删除一个档案会牵动围栏、位置流水、告警、设备绑定和监护关系五处数据，
 * 把这些数字返回给前端，是为了让家属在删除后能看到「到底清掉了多少东西」，
 * 而不是只看到一个"删除成功"却不知道轨迹和告警也一起没了。
 *
 * @param wardId         被删除的档案 id
 * @param geofences      一并删除的围栏条数
 * @param locations      一并删除的位置记录条数
 * @param alerts         一并删除的告警条数
 * @param devicesUnbound 被解绑（而不是删除）的设备台数
 * @param guardians      一并解除的监护关系条数
 */
public record WardDeleteResultVO(
        Long wardId,
        int geofences,
        int locations,
        int alerts,
        int devicesUnbound,
        int guardians
) {
}
