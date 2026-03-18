import { world } from "@minecraft/server";

// afterEvents.chatSend を購読し、サーバーログにチャット内容を出力する。
// LoggiFly の regex パターン: \[ChatLogger\] sender=(?P<sender>.+?) message=(?P<message>.+)
world.afterEvents.chatSend.subscribe((event) => {
    const sender = event.sender?.name ?? "unknown";
    const message = event.message ?? "";
    console.info(`[ChatLogger] sender=${sender} message=${message}`);
});
