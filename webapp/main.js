"use strict";

let canvas = document.getElementById("main_canvas");
let ctx = canvas.getContext("2d");

let wasm = null;

function updateCanvasSize() {
    const update_needed = window.innerHeight && window.innerWidth > 0 &&
                          (canvas.width !== window.innerWidth || canvas.height !== window.innerHeight);
    if (update_needed) {
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
    }
    return update_needed;
}

let prev_timestamp = null;

// window.requestAnimationFrame makes browser call this function before update.
// it calls window.requestAnimationFrame inside creating enternal loop.
function loop(timestamp) {
    if (updateCanvasSize()) {
        wasm.instance.exports.resizeWin(canvas.width, canvas.height);
    }
    let dt = 0;
    if (prev_timestamp !== null) {
        dt = (timestamp - prev_timestamp) * 0.001;
    }
    prev_timestamp = timestamp;

    wasm.instance.exports.update(dt);
    window.requestAnimationFrame(loop);
}

let img = null;
let winning_sound = null

const touches = new Map();

function main(img_promise) {
    updateCanvasSize();

    wasm.instance.exports.setConf(conf.bg_color, conf.shadow_color,
                                  conf.frame_color, conf.frame_width,
                                  conf.border_width, conf.dragging_offset,
                                  conf.puzzle_width, conf.puzzle_height,
                                  conf.snap_radius,
                                  conf.reserved_frame_scale,
                                  conf.bounce_xvel, conf.bounce_yvel,
                                  conf.bounce_slowing, conf.g);

    document.addEventListener("touchstart", (e) => {
        e.preventDefault();
        for (const touch of e.changedTouches) {
            const idx = wasm.instance.exports.eventTouchNew(touch.clientX, touch.clientY);
            if (idx != 0) {
                touches.set(touch.identifier, idx);
            }
        }
    }, false);
    document.addEventListener('touchend', (e) => {
        for (const touch of e.changedTouches) {
            if (!touches.has(touch.identifier)) continue;
            const idx = touches.get(touch.identifier);
            touches.delete(touch.identifier);
            wasm.instance.exports.eventCursorUp(idx);
        }
    }, false);
    document.addEventListener('touchmove', (e) => {
        for (const touch of e.changedTouches) {
            if (!touches.has(touch.identifier)) continue;
            const idx = touches.get(touch.identifier);
            wasm.instance.exports.eventCursorMove(idx, touch.clientX, touch.clientY);
        }
    }, false);


    document.addEventListener('mousedown', (e) => {
        wasm.instance.exports.eventMouseDown();
    }, false);
    document.addEventListener('mouseup', (e) => {
        wasm.instance.exports.eventCursorUp(0);
    }, false);
    document.addEventListener('mousemove', (e) => {
        wasm.instance.exports.eventCursorMove(0, e.clientX, e.clientY);
    }, false);

    img_promise.then(() => {
        if (!wasm.instance.exports.init(canvas.width, canvas.height,
                                        img.naturalWidth, img.naturalHeight,
                                        BigInt((performance.timeOrigin + performance.now() * 1000).toFixed()))) {
            console.log("Initialization failed");
            return;
        }
        window.requestAnimationFrame(loop);
    }).catch((e) => {
        console.log("Image loading is fucked up:", e);
    })
}

const env = {
    jsDrawRect(x, y, w, h, clr) {
        const a = ((clr      ) & 0xff).toString(16).padStart(2, '0');
        const b = ((clr >> 8 ) & 0xff).toString(16).padStart(2, '0');
        const g = ((clr >> 16) & 0xff).toString(16).padStart(2, '0');
        const r = ((clr >> 24) & 0xff).toString(16).padStart(2, '0');
        ctx.fillStyle = '#'+r+g+b+a;
        ctx.fillRect(x, y, w, h);
    },
    jsDrawImgPart(x, y, sx, sy, w, h, img_scale) {
        ctx.drawImage(img, sx, sy, w*img_scale, h*img_scale, x, y, w, h)
    },

    win() {
        winning_sound.play()
        .then(() => {
            new Promise(resolve => setTimeout(resolve, (winning_sound.duration+0.1)*1000))
            .then(() => {
                wasm.instance.exports.timeoutPassed();
            });
        })
        .catch((e) => {
            new Promise(resolve => setTimeout(resolve, conf.final_animation_timeout*1000))
            .then(() => {
                wasm.instance.exports.timeoutPassed();
            });
        });
    },
    log(ptr, len) {
        const mem = wasm.instance.exports.memory.buffer;
        const arr = new Uint8Array(mem, ptr, len);
        const str = new TextDecoder().decode(arr);
        console.log(str);
    },
};

function wasmFetch(src) {
    return WebAssembly.instantiateStreaming(fetch(src), {env: env});
}
function wasmLocal(src) {
    const u8arr = Uint8Array.fromBase64(src);
    return WebAssembly.instantiate(u8arr.buffer, {env: env});
}

function start() {
    img = new Image();
    img.src = conf.image;
    const img_promise = img.decode();

    winning_sound = new Audio(conf.winning_sound);

    let wasm_promise;

    if (conf.wasm_module.type == 0) {
        wasm_promise = wasmFetch(conf.wasm_module.src);
    } else if (conf.wasm_module.type == 1) {
        wasm_promise = wasmLocal(conf.wasm_module.src);
    } else {
        throw new Error("Wrong wasm module type: must be 0 for fetching or 1 for base64");
    }

    wasm_promise.then((w) => {
        wasm = w;
        main(img_promise);
    });
}

start();
