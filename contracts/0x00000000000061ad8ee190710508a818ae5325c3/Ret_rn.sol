// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {
    ERC721A,
    IENS,
    IResolver,
    IENSReverseRegistrar,
    Base64,
    Strings,
    DataContract
} from "./dependencies.sol";

/**
 * @title Ret↵rn
 * @author 0age
 * @notice Generative audiovisual art where all metadata is stored and rendered
 *         onchain. Each musical work is minted in an unrevealed state over an
 *         open, 3 day window from deployment. After the mint phase ends,
 *         entropy is sourced from both a future block and a commited preimage
 *         and used to finalize metadata and reveal the end state of each minted
 *         work. Warning: flashing imagery & audio present.
 */
contract Ret_rn is ERC721A {
    using DataContract for address;
    using Base64 for bytes;
    using Strings for address;
    using Strings for uint256;

    /**
     * @dev Emit an event once the reveal phase has been finalized indicating
     *      that token metadata has been updated.
     *
     * @param fromTokenId The first tokenId (0).
     * @param toTokenId   The last tokenId (totalSupply - 1).
     */
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    /**
     * @dev Emit an event when the reveal phase has been prepared, including
     *      the range of block numbers during which the reveal can be performed.
     *      If the reveal phase is not conducted during this window, owners of
     *      unrevealed tokens are able to burn their tokens to receive a refund
     *      of the mint price.
     *
     * @param firstAvailableRevealBlockNumber The first block number during
     *                                        which the reveal can be performed.
     * @param lastAvailableRevealBlockNumber  The last block number during which
     *                                        the reveal can be performed.
     */
    event Prepare(
        uint256 firstAvailableRevealBlockNumber,
        uint256 lastAvailableRevealBlockNumber
    );

    /**
     * @dev Emit an event when the reveal phase has been completed, displaying
     *      the finalized seed and maximum supply.
     *
     * @param finalizedSeed           The finalized seed set during the reveal.
     * @param finalizedMaximumSupply  The maximum post-reveal token supply.
     */
    event Reveal(bytes32 finalizedSeed, uint256 finalizedMaximumSupply);

    /**
     * @dev Revert with an error if attempting to mint tokens after the
     *      minting phase has been completed.
     */
    error MintCompleted();

    /**
     * @dev Revert with an error if attempting to retrieve a seed for a token
     *      prior to completion of the reveal phase.
     */
    error PreReveal();

    /**
     * @dev Revert with an error if attempting to prepare the reveal phase
     *      before the minting phase has been completed.
     */
    error MintPhaseNotComplete();

    /**
     * @dev Revert with an error if attempting to prepare the reveal phase
     *      multiple times.
     */
    error RevealAlreadyPrepared();

    /**
     * @dev Revert with an error if attempting to conduct the reveal phase
     *      before it has been prepared.
     */
    error RevealNotPrepared();

    /**
     * @dev Revert with an error if attempting to conduct the reveal phase
     *      before the prepared block number has been reached.
     */
    error RevealNotReady();

    /**
     * @dev Revert with an error if attempting to conduct the reveal phase
     *      after the block hash for the prepared block number is no longer
     *      accessible.
     */
    error RevealExpired();

    /**
     * @dev Revert with an error if block entropy used during the reveal phase
     *      is not available.
     */
    error RandomnessNotAvailable();

    /**
     * @dev Revert with an error if attempting to conduct the reveal phase
     *      multiple times.
     */
    error AlreadyRevealed();

    /**
     * @dev Revert with an error if the commit message provided during the
     *      reveal phase does not match the original commit hash.
     */
    error InvalidCommitMessage();

    /**
     * @dev Revert with an error if Ξ0.05 per minted token was not supplied.
     */
    error InvalidMintValue();

    /**
     * @dev Revert with an error if a refund attempt during token burning fails.
     */
    error BurnRefundFailed();

    /**
     * @dev Revert with an error if payment portion of the reveal phase fails.
     */
    error FinalizationFailed();

    /**
     * @dev Revert with an error if `prepareReveal` or `reveal` are called by an
     *      account other than the author as indicated by their ENS record.
     */
    error Unauthorized();

    /**
     * @dev Represent various attributes of a given token as a group of strings.
     */
    struct Attributes {
        string seed;
        string tempo;
        string vibe;
        string root;
        string style;
        string arrow;
        string color;
        string tone;
        string creator;
    }

    // Declare the core ENS registry contract.
    IENS private constant ens = IENS(
        0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e
    );

    // Declare a commit hash that will be used to verify a respective message
    // during the reveal phase before incorporating said message as a component
    // of the final global seed.
    bytes32 private constant commit = bytes32(
        0xdf1b8bdd0db9449895571155d1e7d8ba0b5891111de4164a8ebe2760472961b5
    );

    // Declare an immutable variable representing the time when minting ends.
    uint256 public immutable mintComplete;

    // Declare an immutable variable representing the ENS node for the author.
    bytes32 private immutable authorNode;

    // Declare an immutable variable representing the address of a data
    // contract containing metadata rendering logic.
    address private immutable dataContract;

    // Declare a mapping of token IDs to their respective creators. Note that
    // in instances where a multiple tokens are minted at once, only the first
    // token ID is recorded; when determining the creator of a token with a
    // given ID where a non-zero account value is held in the mapping, the
    // tokenId should be decremented until a non-zero account is located.
    mapping (uint256 => address) private _creators;

    // Declare a state variable representing the global seed. This value is
    // set upon completion of the reveal phase and is used as a component of
    // metadata generation for each token.
    bytes32 public globalSeed;

    // Declare a state variable representing the block number committed to
    // when preparing the reveal phase. The PREVRANDAO value (if available)
    // or the block hash of this block number is used as a component of the
    // final global seed.
    uint256 public revealEntropyBlockNumber;

    /**
     * @dev On contract creation, assign authorship via an ENS name hash,
     *      set the ENS reverse registrar name for this contract, deploy
     *      a new data contract containing rendering logic, and set the
     *      timestamp at which the initial mint phase completes.
     */
    constructor() {
        // Define the authorNode using the ENS name hash of "0age.eth".
        authorNode = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(
                bytes32(0),
                keccak256(abi.encodePacked("eth"))
            )),
            keccak256(abi.encodePacked("0age"))
        ));

        // Derive the ENS reverse registrar node using "reverse.ens.eth".
        bytes32 reverseRegistrarNode = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(
                keccak256(abi.encodePacked(
                    bytes32(0),
                    keccak256(abi.encodePacked("eth"))
                )),
                keccak256(abi.encodePacked("ens"))
            )),
            keccak256(abi.encodePacked("reverse"))
        ));

        // Instantiate the ENS reverse registrar.
        IENSReverseRegistrar ensReverseRegistrar = IENSReverseRegistrar(
            ens.resolver(reverseRegistrarNode).addr(reverseRegistrarNode)
        );

        // Set the name for the ENS reverse registrar.
        ensReverseRegistrar.setName(unicode"ret↩️rn.eth");

        // Declare the initialization code for the data contract containing
        // the rendering logic. The data is prepended with a header that places
        // a single `INVALID` opcode followed by the data in runtime during
        // contract creation.
        bytes memory initCode = abi.encodePacked
            (bytes12(0x600b5981380380925939f3fe),
            '<!doctypehtml><title>Ret&#8629;rn</title><meta content=0age name=author><link href="data:image/svg+xml;base64,PHN2ZyB2aWV3Qm94PSIwIDAgMTAwIDEwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8cmVjdCB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgZmlsbD0iYmxhY2siIC8+CiAgPHRleHQgeD0iNTElIiB5PSI2MCUiIGZvbnQtc2l6ZT0iMTEwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSJsaWdodGdyYXkiIGRvbWluYW50LWJhc2VsaW5lPSJjZW50cmFsIiBmb250LWZhbWlseT0iQXJpYWwiPiYjODYyOTs8L3RleHQ+Cjwvc3ZnPg=="rel=icon type=image/svg+xml><style>body{background-color:#000;height:100%;width:100%;margin:0;padding:0;overflow:hidden}button{height:100vh;width:100vw;position:relative;display:flex;align-items:center;justify-content:center;background:0 0;border:none}#e{position:absolute;top:50%;left:50%;font-size:clamp(1em,51vw,500px);transform:translate(-50%,-50%);color:#d3d3d3}</style><button id=_><span id=e></span></button><script>var seed="0x8a0a40912f2627d9cc3f37b4933f0f15670c5220610e593685634b852482dfdd",sy=[8629,8601,8629,8604,8617,8629,8647,8656,8629,8676,8678,8629,9166,8629,9664,10550];function germinate(e){var $,t=parseInt(e.slice(2,4),16),_=parseInt(e.slice(64),16),n=(t+192)%128+64,i=[2,3,4,6][parseInt(e.slice(4,5),16)>>2],c=[2,3,4,2][parseInt(e.slice(4,5),16)%4],l=[2,3,4,6][parseInt(e.slice(5,6),16)>>2],r=[2,3,4,2][parseInt(e.slice(5,6),16)%4],o=[41.2,43.65,46.25,49,51.91,55,58.27,61.74,65.41,69.3,73.42,77.78,82.41,87.31,92.5,98][parseInt(e.slice(6,7),16)],f=[-2,0,-2,0,3,3,7,10,12,12,12,15.05,15.05,19.1,19.1,24.1][parseInt(e.slice(7,8),16)],u=[3,12,-2,0,3,3,5,7,10,10,12,15.05,15.05,17.05,19.1,24.1][parseInt(e.slice(8,9),16)],p=[-2,0,-2,0,3,5,7,10,12,12,15.05,15.05,12,19.1,24.1,12][parseInt(e.slice(9,10),16)],b=[[8,3],[8,5],[16,5],[16,7],[16,9],[16,10],[16,11],[16,13]],m=_e(_d(...b[parseInt(e.slice(10,11),16)>>1]),t),T=_e(_d(...b[parseInt(e.slice(11,12),16)>>1]),_),g=[[f],[f,u],[f,u,p],[f,f,u,p],[f,u,p,f],[f,u,u,f,p],[f,u,f,f,u],[f,u,0,p,0],[f,0],[f,u,0],[f,0,u,p,0],[0,f,f,0,u],[0,f,u,f,u,p],[0,f,u,u,0,f],[0,f,u,f,f,u],[f,0,0,f,0,u],][parseInt(e.slice(12,13),16)],A=[[0,1,1],[0,1],[0,2],[1,0],[1,2],[2,0,1],[2,1,1],[0,1,0,2],[2,0],[2,1,2],[0,2,1],[0,1,0],[1,2,2],[0,0,1],[0,1,2],[0,0,1,2]][parseInt(e.slice(13,14),16)],v=parseInt(e.slice(14,15),16)>>2,V=parseInt(e.slice(14,15),16)%4+3,y=parseInt(e.slice(15,16),16)>>2,h=parseInt(e.slice(15,16),16)%4+3,q=parseInt(e.slice(16,17),16),R=parseInt(e.slice(17,18),16)>>2,x=parseInt(e.slice(17,18),16)%4,B=sy[parseInt(e.slice(18,19),16)],k=2+parseInt(e.slice(19,20),16),G=parseInt(e.slice(20,22),16),E=parseInt(e.slice(22,23),16),w=4>parseInt(e.slice(23,25),16)?parseInt(e.slice(23,25),16):0,C=15===parseInt(e.slice(25,26),16);return G<189?$="#000000":G<205?$="#ffffff":G<221?$="#ff0000":G<237?$="#00ff00":G<253?$="#0000ff":G<254?($="#ffff00",_f()):G<255?($="#ff00ff",_f()):($="#00ffff",_f()),document.getElementById("e").innerHTML="&#"+B+";",_g($),{seed:e,t:n,b:60/n,p:i,e1:c,e2:l,e3:r,f:o,r1:m,r2:T,fb:t,lb:_,x2:t>>7==1&&n<145,e1s:v,e1i:V,e2s:y,q:g,oq:A,e2i:h,e3s:R,e4s:x,d:q,u:B,sq:k,sk:G,sc:$,sz:E,bt:w,h:C}}function _d(e,$){var t=[],_=[],n=[],i=e-$,c=0;for(n.push($);_.push(Math.floor(i/n[c])),n.push(i%n[c]),i=n[c],!(n[c+=1]<=1););return _.push(i),!function e($){if(-1===$)t.push(!1);else if(-2===$)t.push(!0);else{for(var i=0;i<_[$];i++)e($-1);0!==n[$]&&e($-2)}}(c),t}function _e(e,$){return $%=e.length,e.slice($).concat(e.slice(0,$))}function _f(){document.getElementById("_").style.color="#ffffff"}function _g(e){document.body.style.backgroundColor=e}let lc="#ff0000",sx=parseInt(seed.slice(18,19),16),cx=0;function _h(e,$,t,_=1){let n=lc;lc="#00ff00"===lc?"#0000ff":"#0000ff"===lc?"#ff0000":"#00ff00";var i=setInterval(function(){$.currentTime>=e+.05&&(_g(n),document.getElementById("_").style.color="lightgray",(cx+=_)>=t.sq&&(cx=0),0===cx&&(sx=(sx+t.sz)%sy.length,document.getElementById("e").innerHTML="&#"+sy[sx]+";"),clearInterval(i))},50)}function _i(e,$){return e*Math.pow(2,$/12)}function _j(e,$,t,_,n,i,c,l,r,o=1){t.forEach(({oscillator:t,harmonic:f,volume:u})=>{var p=_*f;t.frequency.setValueAtTime(p,i),t.frequency.setValueAtTime(p,c),t.frequency.linearRampToValueAtTime(n*f,l);var b=$.createGain();b.gain.setValueAtTime(.001,i),b.gain.linearRampToValueAtTime(.25*u*o,i+.01),b.gain.linearRampToValueAtTime(.3*u*o,i+r-.005),b.gain.linearRampToValueAtTime(0,i+r),t.connect(b),b.connect(e),t.start(i),t.stop(i+r),t.onended=function(){b.disconnect(e),t.disconnect(b)}})}function _k(e,$,t,_,n,i,c,l,r,o){t.forEach(({oscillator:t,harmonic:f,volume:u})=>{var p=$.createGain(),b=$.createGain();t.frequency.setValueAtTime(_*f,r),p.gain.setValueAtTime(n*u,r),b.gain.setValueAtTime(i*u,r),p.gain.linearRampToValueAtTime(c*u,r+o),b.gain.linearRampToValueAtTime(l*u,r+o);var m=$.createDelay();m.delayTime.setValueAtTime(.04,r),t.connect(p),t.connect(m),p.connect(e),b.connect(e),t.start(r),t.stop(r+o),t.onended=function(){p.disconnect(e),b.disconnect(e),t.disconnect(),m.disconnect()}})}function _l(e,$,t,_,n,i,c,l,r,o){t.forEach(({oscillator:t,harmonic:f,volume:u})=>{var p=_*f;t.frequency.setValueAtTime(p,c),t.frequency.setValueAtTime(p,c+o);var b=$.createGain();b.gain.setValueAtTime(1e-4*u,c),b.gain.linearRampToValueAtTime(.4*u,c+.01),b.gain.linearRampToValueAtTime(.3*u,c+o-.05),b.gain.linearRampToValueAtTime(.1*u,c+o-.02),b.gain.exponentialRampToValueAtTime(.001*u,c+o);var m=$.createBiquadFilter();m.type="lowpass",m.frequency.setValueAtTime(n,c),m.frequency.setValueAtTime(n,l),m.frequency.linearRampToValueAtTime(i,r),t.connect(m),m.connect(b),b.connect(e),t.start(c),t.stop(c+o),t.onended=function(){b.disconnect(e),m.disconnect(b),t.disconnect(m)}})}function _m(e,$,t,_,n,i,c,l=!1){let r=i/c;t.forEach(({oscillator:t,harmonic:o,volume:f})=>{var u=_*o;t.frequency.setValueAtTime(u,n),t.frequency.setValueAtTime(u,n+i);var p=$.createGain();p.gain.setValueAtTime(1e-4*f,n);for(let b=0;b<c;++b){let m=l?(b+1)/(3*c/2):1,T=n+r*b;p.gain.setValueAtTime(1e-4*f,T),p.gain.linearRampToValueAtTime(.15*f*m*c/2,T+.01),p.gain.exponentialRampToValueAtTime(.075*f*m*c/2,T+3*r/4-.05),p.gain.linearRampToValueAtTime(.001*f,T+3*r/4),p.gain.linearRampToValueAtTime(.001*f,T+r-.02)}p.gain.exponentialRampToValueAtTime(.001*f,n+i),t.connect(p),p.connect(e),t.start(n),t.stop(n+i),t.onended=function(){p.disconnect(e),t.disconnect(p)}})}function _n(e,$,t,_,n,i,c){c<4&&(c*=2);let l=[0,12,19,24,31,36,0,12,19,24,31,36],r=i/c;t.forEach(({oscillator:t,harmonic:o,volume:f})=>{var u=_*o;t.frequency.setValueAtTime(u,n);var p=$.createGain();p.gain.setValueAtTime(1e-4*f,n);for(let b=0;b<c;++b){let m=n+r*b;t.frequency.setValueAtTime(_i(u,l[b]),m),p.gain.setValueAtTime(1e-4*f,m),p.gain.linearRampToValueAtTime(.13*f*(12-b)/12,m+.01),p.gain.exponentialRampToValueAtTime(.065*f*(12-b)/12,m+7*r/8-.05),p.gain.linearRampToValueAtTime(.001*f,m+7*r/8),p.gain.linearRampToValueAtTime(.001*f,m+r-.02)}p.gain.exponentialRampToValueAtTime(.001*f,n+i),t.connect(p),p.connect(e),t.start(n),t.stop(n+i),t.onended=function(){p.disconnect(e),t.disconnect(p)}})}function _o(e,$,t,_,n,i,c,l,r,o,f=1){t.forEach(({oscillator:t,harmonic:u,volume:p})=>{var b=_*u;t.frequency.setValueAtTime(b,c),t.frequency.setValueAtTime(b,c+o);var m=$.createGain();m.gain.setValueAtTime(.15*p*f,c),m.gain.linearRampToValueAtTime(.25*p*f,c+o-.005),m.gain.linearRampToValueAtTime(0,c+o);var T=$.createBiquadFilter();T.type="highpass",T.frequency.setValueAtTime(n,c),T.frequency.setValueAtTime(n,l),T.frequency.linearRampToValueAtTime(i,r),t.connect(T),T.connect(m),m.connect(e),t.start(c),t.stop(c+o),t.onended=function(){m.disconnect(e),T.disconnect(m),t.disconnect(T)}})}function _p(e,$,t,_=1){var n=$.createOscillator(),i=$.createGain();n.connect(i),i.connect(e),n.frequency.setValueAtTime(130,t),n.frequency.exponentialRampToValueAtTime(30,t+.2);var c=t+.01;i.gain.setValueAtTime(.7*_,t),i.gain.setValueAtTime(.7*_,c),i.gain.exponentialRampToValueAtTime(.001*_,t+.2),n.start(t),n.stop(t+.2);var l=$.createOscillator(),r=$.createGain();l.connect(r),r.connect(e),l.frequency.setValueAtTime(65,t),l.frequency.exponentialRampToValueAtTime(15,t+.2),r.gain.setValueAtTime(.25,t),r.gain.setValueAtTime(.2,c),r.gain.exponentialRampToValueAtTime(.001,t+.2),l.start(t),l.stop(t+.2);for(var o=t,f=$.sampleRate,u=$.createBuffer(1,f,$.sampleRate),p=u.getChannelData(0),b=0;b<f;b++)p[b]=2*Math.random()-1;var m=$.createBufferSource();m.buffer=u;var T=$.createGain();m.connect(T),T.connect(e),T.gain.setValueAtTime(.2,o),T.gain.setValueAtTime(.1,o+.01),T.gain.exponentialRampToValueAtTime(.001,o+.1),m.start(o),m.stop(o+.1);var g=setInterval(function(){$.currentTime>=t&&(_g("#000000"),clearInterval(g))},25)}function _q(e,$,t){for(var _=$.sampleRate,n=$.createBuffer(1,_,$.sampleRate),i=n.getChannelData(0),c=0;c<_;c++)i[c]=2*Math.random()-1;var l=$.createBufferSource();l.buffer=n;var r=$.createBiquadFilter();r.type="highpass",r.frequency.value=6e3;var o=$.createGain();l.connect(r),r.connect(o),o.connect(e),o.gain.setValueAtTime(.1,t),o.gain.exponentialRampToValueAtTime(.001,t+.08),l.start(t),l.stop(t+.08)}function _s(e,$,t,_,n=!1){for(var i=$.sampleRate,c=$.createBuffer(1,i,$.sampleRate),l=c.getChannelData(0),r=0;r<i;r++)l[r]=2*Math.random()-1;var o=$.createBufferSource();o.buffer=c;var f=$.createBiquadFilter();f.type="highpass",f.frequency.value=n?7e3:5500;var u=$.createGain();o.connect(f),f.connect(u),u.connect(e);var p=n?.1:.15;u.gain.setValueAtTime(p,t),u.gain.setValueAtTime(n?0:p,t+.05),o.start(t),o.stop(t+_)}function _t(e,$,t){for(var _=$.sampleRate,n=$.createBuffer(1,_,$.sampleRate),i=n.getChannelData(0),c=0;c<_;c++)i[c]=2*Math.random()-1;var l=$.createBufferSource();l.buffer=n;var r=$.createBiquadFilter();r.type="highpass",r.frequency.value=3500;var o=$.createGain();l.connect(r),r.connect(o),o.connect(e),t-=.2,o.gain.setValueAtTime(.001,t),o.gain.exponentialRampToValueAtTime(.07,t+.2),l.start(t),l.stop(t+.2)}function _u(e,$,t){for(var _=$.createBufferSource(),n=$.createBuffer(1,$.sampleRate/10,$.sampleRate),i=$.createGain(),c=n.getChannelData(0),l=0;l<c.length;l++)c[l]=2*Math.random()-1;_.buffer=n,_.connect(i),i.connect(e),i.gain.setValueAtTime(.4,t),i.gain.exponentialRampToValueAtTime(.2,t+.01),i.gain.exponentialRampToValueAtTime(.01,t+.2),_.start(t),_.stop(t+.2);var r=setInterval(function(){$.currentTime>=t&&(_g("#ffffff"),clearInterval(r))},25)}function _v(e){return function($){return e.map(([e,t,_])=>{var n=$.createOscillator();return n.type=["sine","triangle","square","sawtooth"][e],{oscillator:n,harmonic:t,volume:_}})}}const d=[[[3,1,.2],[2,3,.03],[1,6,.1]],[[0,1,1],[2,1,.4],[1,2,.15],[3,4,.15]],[[1,1,1],[0,2,.3],[0,3,.06],[3,3,.02],[3,6,.01]],[[0,1,1],[3,1,.03],[1,2,.025],[0,4,.016],[1,4,.008],[1,8,.002]],[[3,1,1],[1,2,.6],[3,4.75,.15],[0,6,.2],[3,9.5,.05],[3,8,.1]],[[3,1,.3],[1,1,1],[1,3,.3],[1,7,.4]],[[0,1,1],[0,2,.3],[0,2,.5],[3,3.56,.3],[3,7.12,.2]]].map(_v);function _w(e,$,t,_,n){let i=0;if(0===e.d||4===e.d||12===e.d)for(let c=_;c<_+960/e.t-.01;c+=120/e.t)0!==n&&i%8==0&&_t($,t,c),i+=1,_p($,t,0===n&&c===_?c:c-.003);else if(1===e.d||5==e.d||13==e.d)for(let l=_;l<_+960/e.t-.01;l+=240/e.t)0!==n&&i%4==0&&_t($,t,l),i+=1,_p($,t,0===n&&l===_?l:l-.003);else if(2===e.d||6==e.d||14===e.d||15===e.d)for(let r=_;r<_+900/e.t-.01;r+=60/e.t)0!==n&&i%8==0&&_t($,t,r),i+=1,_p($,t,0===n&&r===_?r:r-.003);else if(3===e.d||7===e.d||8===e.d)for(let o=_;o<_+900/e.t-.01;o+=60/e.t)0!==n&&i%8==0&&_t($,t,o),_p($,t,0===n&&o===_?o:o-.003),i%2==0&&i<15&&_p($,t,o+e.b*(1-1/e.p)-.003,.1),i+=1;else if(9===e.d)for(let f=_;f<_+900/e.t-.01;f+=120/e.t)0!==n&&i%8==0&&_t($,t,f),(i+=1)%2==0?_p($,t,f+e.b*(1-1/e.p)-.003,.1):_p($,t,f);else if(10===e.d||11===e.d)for(let u=_;u<_+900/e.t-.01;u+=60/e.t)0!==n&&i%8==0&&_t($,t,u),i%2==0&&_p($,t,0===n&&u===_?u:u-.003),i%2==1&&_p($,t,u+e.b*(e.p%3==0?1/3:1/4)-.003),i+=1;7===n&&_p($,t,_+960/e.t)}function _x(e,$,t,_){let n=0;if(0===e.d||2===e.d||12===e.d)for(let i=_+60/e.t;i<_+960/e.t;i+=120/e.t)n%8==3&&_t($,t,i+.001),n+=1,_u($,t,i);else if(1===e.d||13==e.d)for(let c=_+120/e.t;c<_+960/e.t;c+=240/e.t)n%4==3&&_t($,t,c+.001),n+=1,_u($,t,c);else if(3===e.d||8===e.d||14===e.d)for(let l=_+30/e.t;l<_+840/e.t;l+=60/e.t)n%8==3&&_t($,t,l+.001),n+=1,_u($,t,l);else if(4===e.d||5===e.d||6==e.d||7===e.d)for(let r=_+60/e.t;r<_+960/e.t;r+=120/e.t)n%8==3&&_t($,t,r+.001),n&&n%8%3==0?(_u($,t,r-e.b*(1/e.p)-.003,.1),_u($,t,r+e.b*(3===e.p?2/3:.5)-.003,.1)):_u($,t,r),n+=1;else if(9===e.d)for(let o=_+60/e.t;o<_+900/e.t;o+=120/e.t)n%8==3&&n<13&&_t($,t,o+.001),(n+=1)<13&&(n%2==1&&n<11?(n%3==1&&_u($,t,o-e.b*(1/e.p)-.003,.1),_u($,t,o+e.b*(3===e.p?2/3:.5)-.003,.1)):_u($,t,o+e.b*(3===e.p?2/3:.5)));else if(10===e.d)for(let f=_+60/e.t;f<_+900/e.t;f+=60/e.t)n%8==3&&_t($,t,f+.001),(n+=1)<15&&(n%2==1?(n%3==1&&_u($,t,f-e.b*(1/e.p)-.003,.1),_u($,t,f+e.b*(3===e.p?2/3:.5)-.003,.1)):_u($,t,f+e.b*(3===e.p?2/3:.5)));else if(11===e.d)for(let u=_;u<_+900/e.t;u+=60/e.t)n<15&&(n%2==1?(_u($,t,u-e.b*(1/e.p)-.003,.1),_u($,t,u+e.b*(3===e.p?2/3:.5)-.003,.2)):_u($,t,u+e.b*(3===e.p?2/3:.5),.3)),n+=1}function _y(e,$,t,_,n){let i=0;for(let c=_;c<_+60/e.t-.01;c+=60/(e.t*e.e1))i=i%e.e1+1,(6!==e.e1||2!==i&&5!=i)&&_s($,t,0===n&&c===_?c:c-.001,30/(e.t*e.e1));i=0;for(let l=_+60/e.t;l<_+480/e.t;l+=60/(e.t*e.p))i=i%e.p+1,(6!==e.p||2!==i&&5!=i)&&_q($,t,0===n&&l===_?l:l-.001);i=0;for(let r=_+480/e.t;r<_+540/e.t-.01;r+=60/(e.t*e.e2))i=i%e.e2+1,(6!==e.e2||2!==i&&5!=i)&&_s($,t,0===n&&r===_?r:r-.001,30/(e.t*e.e2));i=0;for(let o=_+540/e.t;o<_+840/e.t;o+=60/(e.t*e.p))i=i%e.p+1,(6!==e.p||2!==i&&5!=i)&&_q($,t,0===n&&o===_?o:o-.001);i=0;for(let f=_+840/e.t;f<_+960/e.t;f+=60/(e.t*e.e3))i=i%e.e3+1,(6!==e.e3||2!==i&&5!=i)&&_q($,t,0===n&&f===_?f:f-.001)}function _1(e,$,t,_,n,i=!1,c){let l=0,r=0,o=0,f=0;for(let u=_;u<_+960/e.t-.01;u+=60/(e.t*e.p))if(f=f%e.p+1,e.p%3!=0||2!==f&&5!==f){if(u>_+60/e.t+.001&&!(u>_+480/e.t-.001&&u<_+540/e.t+.001)&&u<_+840/e.t-.001&&e.r1[l]){let p=(l<e.r1.length&&!e.r1[l+1]?2*e.b/e.p:e.b/e.p)*(6===e.p&&1!==f&&4!==f?.5:1)*(6===e.p&&e.x2?2:1)*(3===e.p&&1===f?1.5:.75)*(2===e.p&&e.t<140?.5:1)*(i?2:1)*(4===e.p&&!e.x2&&e.t<145?.5:1)*(6===e.p&&e.t>144?2:1);1===f?_l($,t,c[e.oq[o]](t),_i(e.f,e.q[r]),100,750,u,u,u+p,p):_j($,t,c[e.oq[o]](t),_i(e.f,e.q[r]),_i(e.f,e.q[r]),u,u+p/2,u+3*p/4,p),_h(u,t,e),r+=1,r%=e.q.length,o+=1,o%=e.oq.length}l+=1,l%=e.r1.length}}function _2(e,$,t,_){let n=_+60/e.t;if(1===e.bt){_o($,t,d[1](t),_i(e.f,31),3e3,600,n,n+e.b/3,n+2*e.b/3,e.b,.3);for(let i=_+120/e.t;i<_+840/e.t-.01;i+=120/(e.t*e.p))_o($,t,d[1](t),_i(e.f,31),3e3,700,i,i+e.b/3,i+2*e.b/3,e.b,.2)}else if(2===e.bt){_o($,t,d[2](t),_i(e.f,36),4e3,600,n,n+e.b/3,n+2*e.b/3,e.b,.5);for(let c=_+120/e.t;c<_+840/e.t-.01;c+=120/(e.t*e.p))_o($,t,d[2](t),_i(e.f,36),1800,700,c,c+e.b/3,c+2*e.b/3,e.b,.4)}else if(3===e.bt){_o($,t,d[3](t),_i(e.f,51.08),2e3,700,n,n+e.b/3,n+2*e.b/3,e.b,.22);for(let l=_+120/e.t;l<_+840/e.t-.01;l+=120/(e.t*e.p))_o($,t,d[3](t),_i(e.f,51.08),3e3,800,l,l+e.b/3,l+2*e.b/3,e.b,.15)}}function _z(e,$,t,_,n){let i=0,c=0,l=0,r=0;for(let o=_;o<_+960/e.t-.01;o+=60/(e.t*e.p))r=r%e.p+1,(e.p%3!=0||2!==r&&5!==r)&&(o>_+60/e.t+.001&&!(o>_+480/e.t-.001&&o<_+540/e.t+.001)&&o<_+840/e.t-.001&&e.r2[i]&&(_s($,t,0===n&&o===_?o:o-.001,(i<e.r2.length&&!e.r2[i+1]?2*e.b/e.p:e.b/e.p)*(6===e.p&&1!==r&&4!==r?.3:.6)*(6===e.p&&e.x2?2:1)*(3===e.p&&1===r?2:1),!0),c+=1,c%=e.q.length,l+=1,l%=e.oq.length),i+=1,i%=e.r2.length)}function _b(e,$,t,_,n,i){e.h||(_w(e,$,t,_,n),_x(e,$,t,_),_y(e,$,t,_,n),_z(e,$,t,_,n)),_1(e,$,t,_,n,!e.x2&&(2===e.p||4===e.p&&e.t<145),i),0!==e.bt&&_2(e,$,t,_),_h(_,t,e,5),0===e.e1s?_l($,t,i[e.e1i](t),e.f,50,300,_,_+e.b/2,_+3*e.b/4,e.b):1===e.e1s?_n($,t,i[e.e1i](t),e.f,_,e.b,e.e1):2===e.e1s?_j($,t,i[e.e1i](t),e.f,_i(e.f,12),_,_+e.b/2,_+3*e.b/4,e.b,.6):3===e.e1s&&_m($,t,i[e.e1i](t),e.f,_,e.b,e.e1),_k($,t,d[0](t),_i(e.f,63.2),.005,.005,0,.01,_+e.b,e.b),_h(_+8*e.b,t,e,3),0===e.e2s?_l($,t,i[e.e2i](t),e.f,200,600,_+8*e.b,_+8*e.b+e.b/2,_+8*e.b+3*e.b/4,e.b):1===e.e2s?_m($,t,i[e.e2i](t),e.f,_+8*e.b,e.b,e.e2):2===e.e2s?_j($,t,i[e.e2i](t),_i(e.f,12),e.f,_+8*e.b,_+8*e.b+e.b/2,_+8*e.b+3*e.b/4,e.b,.6):3===e.e2s&&_n($,t,i[e.e2i](t),e.f,_+8*e.b,e.b,e.e2),_k($,t,d[0](t),_i(e.f,60.2),.005,.005,0,.01,_+9*e.b,e.b),_k($,t,d[0](t),_i(e.f,36.07),.009,.009,0,.018,_+15*e.b,e.b),_h(_+15*e.b,t,e),n%2==0?0===e.e3s?(_j($,t,d[3](t),_i(e.f,e.lb>127?0:12),_i(e.f,e.lb>127?12:0),_+14*e.b,_+14*e.b+e.b/2,_+14*e.b+3*e.b/4,e.b),_o($,t,d[1](t),_i(e.f,e.fb>127?3:-2),4e3,500,_+15*e.b,_+15*e.b+e.b/2,_+15*e.b+3*e.b/4,e.b)):1===e.e3s?_n($,t,i[e.e1i](t),e.f,_+14*e.b,2*e.b,2*e.e3):2===e.e3s?(_l($,t,d[1](t),_i(e.f,3),50,400,_+14*e.b,_+14*e.b+e.b/2,_+14*e.b+3*e.b/4,e.b),_l($,t,d[1](t),_i(e.f,2),300,3e3,_+15*e.b,_+15*e.b+e.b/2,_+15*e.b+3*e.b/4,e.b)):3===e.e3s&&_m($,t,i[e.e1i](t),_i(e.f,e.fb%2==0?0:-2),_+14*e.b,2*e.b,2*e.e3,!0):0===e.e4s?(_j($,t,d[3](t),_i(e.f,e.lb>127?0:12),_i(e.f,e.lb>127?12:0),_+14*e.b,_+14*e.b+e.b/2,_+14*e.b+3*e.b/4,e.b),_o($,t,d[1](t),_i(e.f,e.fb>127||7===n?3:-2),4e3,500,_+15*e.b,_+15*e.b+e.b/2,_+15*e.b+3*e.b/4,e.b)):1===e.e4s?_o($,t,d[1](t),_i(e.f,e.fb>127||7===n?3:-2),5e3,200,_+14*e.b,_+14*e.b+e.b/2,_+15*e.b+3*e.b/4,2*e.b):2===e.e4s?(_n($,t,i[e.e1i](t),e.f,_+14*e.b,e.b,e.e3),_n($,t,i[e.e2i](t),e.f,_+15*e.b,e.b,e.e3)):3===e.e4s&&_m($,t,i[e.e1i](t),_i(e.f,e.fb%2==0||7===n?0:-2),_+14*e.b,2*e.b,4*e.e3,!0)}function _r(e){let $=e.sampleRate,t=.3*$,_=e.createBuffer(2,t,$),n=_.getChannelData(0),i=_.getChannelData(1),c,l,r,o,f,u,p;function b(){let e=2*Math.random()-1;return c=.99886*c+.0555179*e,l=.99332*l+.0750759*e,r=.969*r+.153852*e,o=.8665*o+.3104856*e,c+l+r+o+(f=.55*f+.5329522*e)+(u=-.7616*u-.016898*e)+p+.5362*e}c=l=r=o=f=u=p=0;for(let m=0;m<t;m++){let T=m/$,g=b();n[m]=g*Math.pow(1-T/.3,2),i[m]=g*Math.pow(1-T/.3,2)}let A=e.createConvolver();A.buffer=_;let v=e.createGain(),V=e.createGain();return v.gain.value=.875,V.gain.value=.125,{connect:function(e,$){e.connect(A),A.connect(V),V.connect($),e.connect(v),v.connect($)}}}function _c(e,$,t){let _=[],n=$.createDynamicsCompressor();n.threshold.value=-.1,n.knee.value=0,n.ratio.value=20,n.attack.value=0,n.release.value=.01;let i=$.createGain();i.gain.value=1,e.connect(i),i.connect(n);for(let c=0;c<t.length;c++){let l=t[c],r=$.createBiquadFilter();r.type="lowpass",r.frequency.value=l.x;let o=$.createBiquadFilter();o.type="highpass",o.frequency.value=c>0?t[c-1].x:0;let f=$.createDynamicsCompressor();f.threshold.value=l.t,f.knee.value=l.k,f.ratio.value=l.o,f.attack.value=l.a,f.release.value=l.r;let u=$.createGain();u.gain.value=l.g;let p=$.createGain();p.gain.value=.9,0===c?e.connect(o):_[c-1].lowpass.connect(o),o.connect(r),r.connect(f),f.connect(p),p.connect(u),u.connect(n),_.push({lowpass:r,highpass:o,compressor:f,gain:u,normalizationGain:p})}return _r($).connect(n,$.destination),_}function _a(e){_g("grey"),a=new(window.AudioContext||window.webkitAudioContext);let $=[d[3],d[0],d[2],d[1],d[4],d[5],d[6]],t=a.createGain();t.gain.value=1,_c(t,a,[{x:75,t:-30,k:30,o:3,a:.01,r:.37,g:1},{x:150,t:-30,k:30,o:3,a:.03,r:.33,g:1.1},{x:400,t:-30,k:35,o:8,a:.01,r:.3,g:.8},{x:700,t:-30,k:40,o:12,a:.005,r:.25,g:.4},{x:2e3,t:-30,k:40,o:14,a:.002,r:.23,g:.3},{x:4e3,t:-30,k:40,o:16,a:.001,r:.2,g:.2},{x:a.sampleRate/2,t:-30,k:40,o:4,a:.001,r:.15,g:.2},]);let _=a.currentTime+.3;for(let n=0;n<8;++n)setTimeout(function(){_b(e,t,a,_+960/e.t*n+.1,n,$)},2e3*n)}const s=germinate(seed);console.log(s);var db=128e3*s.b+200,le=0;document.getElementById("_").addEventListener("click",function(){var e=Date.now();e-le>db&&(_a(s),le=e)}),window.addEventListener("keyup",function(e){var $=Date.now();"Enter"===e.key&&$-le>db&&(document.getElementById("_").click(),le=$)});</script>'
        );

        // Create a new contract using the initialization code.
        address addr;
        assembly {
            addr := create(0, add(initCode, 0x20), mload(initCode))
        }

        // Assign the new contract's address to the data contract.
        dataContract = addr;

        // Set the timestamp at which the mint phase completes.
        mintComplete = block.timestamp + 3 days;
    }

    /**
     * @dev Supply Ξ0.05 and mint a single token to the caller. Minting is
     *      possible until 3 days after contract deployment. Minted token will
     *      be in an unrevealed state until the mint completes and additional
     *      entropy is added. Provenance is established by permanently storing
     *      the address of the caller as the creator of the respective token
     *      and incorporating it into the seed that determines its attributes.
     */
    function mint() external payable {
        _create(msg.sender, 1);
    }

    /**
     * @dev Mint an arbitrary quantity of tokens to the caller, supplying Ξ0.05
     *      per work minted. Minting is possible until 3 days after contract
     *      deployment. Minted token will be in an unrevealed state until the
     *      mint completes and additional randomness is added. Provenance is
     *      established by permanently storing the address of the caller as the
     *      creator of the respective token and incorporating it into the seed
     *      that determines its attributes.
     *
     * @param amount The amount of tokens to mint.
     */
    function mint(uint256 amount) external payable {
        _create(msg.sender, amount);
    }

    /**
     * @dev Mint an arbitrary quantity of tokens to the a specified account,
     *      supplying Ξ0.05 per work minted. Minting is possible until 3 days
     *      after contract deployment. Minted token will be in an unrevealed
     *      state until the mint completes and additional randomness is added.
     *      Provenance is established by permanently storing the address of the
     *      caller as the creator of the respective token and incorporating it
     *      into the seed that determines its attributes.
     *
     * @param to The address to send the minted tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external payable {
        _create(to, amount);
    }

    /**
     * @dev Prepare for the reveal phase by setting a future block number that
     *      will be used to derive additional entropy when revealing tokens.
     *      This function can only be called by the author and only after the
     *      mint phase is complete, or 3 days after contract deployment. A
     *      `RevealAlreadyPrepared` error will be thrown if an attempt is made
     *      to prepare the reveal phase multiple times.
     *
     * @return firstAvailableRevealBlockNumber The first block number that the
     *                                         reveal can be performed.
     * @return lastAvailableRevealBlockNumber  The last block number that the
     *                                         reveal can be performed.
     */
    function prepareReveal() external returns (
        uint256 firstAvailableRevealBlockNumber,
        uint256 lastAvailableRevealBlockNumber
    ) {
        // Only the author can prepare the reveal phase.
        _onlyAuthor();

        // Ensure mint phase is complete before reveal phase can be prepared.
        if (mintComplete > block.timestamp) {
            revert MintPhaseNotComplete();
        }

        // Ensure that the reveal phase can only be prepared once.
        if (revealEntropyBlockNumber != uint256(0)) {
            revert RevealAlreadyPrepared();
        }

        // Set the block number that will be used to derive additional
        // entropy during the reveal phase. Assign a block number that
        // is 64 blocks in the future to protect against selecting for
        // a specific block proposer.
        revealEntropyBlockNumber = block.number + 0x40;

        // Set block number range during which reveal can be performed.
        firstAvailableRevealBlockNumber = revealEntropyBlockNumber + 1;
        lastAvailableRevealBlockNumber = revealEntropyBlockNumber + 0xff;

        // Emit an event to signal the preparation of the reveal phase,
        // including the range of block numbers during which the reveal
        // can be performed.
        emit Prepare(
            firstAvailableRevealBlockNumber,
            lastAvailableRevealBlockNumber
        );
    }

    /**
     * @dev Reveal final attributes and metadata by setting a global seed to a
     *      derived from the block number assigned when preparing to reveal and
     *      from a message that hashes to a value committed during deployment.
     *      This function can only be called by the author and only after the
     *      reveal phase has been prepared. An "AlreadyRevealed" error will be
     *      thrown if an attempt is made to reveal multiple times. Triggering
     *      reveal on the first available block is preferable, as PREVRANDAO is
     *      more resistant to biasability than block hashes. Should the author
     *      fail to successfully finalize the reveal during this period, owners
     *      of unrevealed tokens are able to burn those tokens to receive a
     *      refund of the mint price.
     *
     * @param commitMessage The commit message used during the reveal.
     *
     * @return finalizedSeed The finalized seed used for the reveal.
     */
    function reveal(
        string calldata commitMessage
    ) external returns (bytes32 finalizedSeed) {
        // Only the author can finalize the reveal phase.
        address payable authorAccount = _onlyAuthor();

        // Ensure that the reveal has not already been conducted.
        if (globalSeed != bytes32(0)) {
            revert AlreadyRevealed();
        }

        // Ensure supplied commit message matches original commit hash.
        if (keccak256(bytes(commitMessage)) != commit) {
            revert InvalidCommitMessage();
        }

        // Retrieve the block number committed to during the prepare phase.
        uint256 randomnessBlockNumber = revealEntropyBlockNumber;

        // Ensure that the reveal phase has been prepared.
        if (randomnessBlockNumber == uint256(0)) {
            revert RevealNotPrepared();
        }

        // Ensure that the reveal phase has started.
        if (randomnessBlockNumber >= block.number) {
            revert RevealNotReady();
        }

        // Ensure that the reveal phase has not ended.
        if (randomnessBlockNumber + 0xff < block.number) {
            revert RevealExpired();
        }

        // Declare a value for the randomness sourced from that block.
        uint256 randomness;

        // Use PREVRANDAO if available — it is only available on the
        // first block after the reveal phase has started.
        if (randomnessBlockNumber == block.number - 1) {
            randomness = block.prevrandao;
        }

        // Otherwise, use the blockhash as a fallback.
        if (randomness == 0) {
            randomness = uint256(blockhash(randomnessBlockNumber));
        }

        // Sanity check to ensure a non-zero randomness was located.
        if (randomness == 0) {
            revert RandomnessNotAvailable();
        }

        // Derive finalized seed using the chain id, the contract address,
        // the randomness sourced from the block, and the commit message.
        finalizedSeed = keccak256(abi.encodePacked(
            block.chainid,
            address(this),
            randomness,
            commitMessage
        ));

        // Set the global seed to the finalized seed.
        globalSeed = finalizedSeed;

        // Transfer any remaining contract balance to the author.
        (bool ok, ) = authorAccount.call{value: address(this).balance}("");

        // If the transfer fails, revert the transaction.
        if (!ok) {
            // Use assembly to "bubble up" return data if available and not
            // excessively long.
            assembly {
                if and(returndatasize(), lt(returndatasize(), 0xffffff)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }

            // Otherwise, revert with a generic error.
            revert FinalizationFailed();
        }

        // Determine the total supply of tokens.
        uint256 maxSupply = totalSupply();

        // Emit event to indicate finalization of metadata and max supply.
        emit Reveal(finalizedSeed, maxSupply);

        // Emit event to indicate that all metadata has been updated. Note
        // that some tokens may not be included if any have been burned and
        // will have to be updated manually.
        emit BatchMetadataUpdate(0, maxSupply - 1);

        // Return the finalized seed value.
        return finalizedSeed;
    }

    /**
     * @dev Burn a given token assuming that the caller is the owner or has been
     *      approved by the owner. If more than 30 minutes have passed since the
     *      minting phase has completed and the reveal phase has not yet been
     *      finalized, the owner of the token will receive a refund of the mint
     *      price. Note that there is a danger that a token may be burned even
     *      when it is not eligible for a refund; if a refund is expected, using
     *      `burnUnrevealedAndRefund` is recommended.
     */
    function burn(uint256 id) external {
        // Burn the token and perform a refund if applicable.
        _destroy(id);
    }

    /**
     * @dev Burn a given unrevealed token and ensure that a refund of the
     *      mint price is received by the owner, assuming that the caller is
     *      the owner or has been approved by the owner. This function is only
     *      callable if more than 30 minutes have passed since the minting phase
     *      has completed and the reveal phase has not yet been finalized. While
     *      `burn` may also be used for this purpose, there is a danger that the
     *      token may be burned even when it is not eligible for a refund.
     */
    function burnUnrevealedAndRefund(uint256 id) external {
        // Ensure that the reveal phase has not been finalized.
        if (globalSeed != bytes32(0)) {
            revert AlreadyRevealed();
        }

        // Burn the token and ensure that a refund is performed.
        if (!_destroy(id)) {
            revert BurnRefundFailed();
        }
    }

    /**
     * @dev Get the address of the account that minted a specified token. Note
     *      that this function can consume a significant amount of gas in cases
     *      where the creator minted many tokens at once.
     *
     * @param id The id of the token in question.
     *
     * @return creator The address of the account that minted the token.
     */
    function getCreator(uint256 id) external view returns (address) {
        // Ensure that a token with the given id exists.
        if (!_exists(id)) {
            revert URIQueryForNonexistentToken();
        }

        // Retrieve and return the creator of the specified token.
        return _getCreator(id);
    }

    /**
     * @dev Get the "seed" for a given id. The seed is derived from the
     *      token's id, the global seed, and the address of the account
     *      that minted the token. This function will revert unless the
     *      global seed has been finalized.
     *
     * @param id The id of the token in question.
     */
    function getSeed(uint256 id) external view returns (bytes32) {
        // Ensure that a token with the given id exists.
        if (!_exists(id)) {
            revert URIQueryForNonexistentToken();
        }

        // Retrieve the global seed value from storage.
        bytes32 randomness = globalSeed;

        // Revert if the global seed has not been finalized.
        if (randomness == bytes32(0)) {
            revert PreReveal();
        }

        // Derive and return the seed of the specified token.
        return _getSeed(id, globalSeed);
    }

    /**
     * @dev Get the SVG associated with the specified id. The default image
     *      will be returned unless the global seed has been finalized.
     *
     * @param id The id of the token in question.
     */
    function image(uint256 id) external view returns (string memory) {
        // Ensure that a token with the given id exists.
        if (!_exists(id)) {
            revert URIQueryForNonexistentToken();
        }

        // Return image for the token (do not supply a previously-derived seed).
        return _image(id, globalSeed, bytes32(0));
    }

    /**
     * @dev Get the address currently resolved by the ENS name hash of the
     *      author of this artwork.
     */
    function author() public view returns (address) {
        return ens.resolver(authorNode).addr(authorNode);
    }

    /**
     * @dev Get the ERC721 metadata for the token with the specified id. The
     *      metadata is formatted as a dataURI containing a JSON object
     *      containing the name, description, and attributes of the token as
     *      well as a dataURI-encoded SVG image and a dataURI animation_url
     *      containing an html document with web audio code for playing the song
     *      and animation of the token. The html document itself is retrieved
     *      from a data contract and the token's seed is inserted into the code;
     *      this seed determines what audiovisual content will be rendered. The
     *      metadata is only finalized once the global seed has been set, and
     *      will otherwise return a default image and metadata.
     *
     * @param id The id of the token in question.
     */
    function tokenURI(uint256 id) public view override returns (string memory) {
        // Ensure that a token with the given id exists.
        if (!_exists(id)) {
            revert URIQueryForNonexistentToken();
        }

        // Read the global seed value from storage and use as entropy.
        bytes32 entropy = globalSeed;

        // Derive the seed for the given token using the id and entropy.
        bytes32 seed = _getSeed(id, entropy);

        // Construct and return the token metadata.
        return string.concat(
            'data:application/json;base64,',
            bytes(
                string.concat(
                    unicode'{"name":"Ret↵rn — #',
                    id.toString(),
                    '","description":"Generative audiovisual art where all metadata is stored and rendered onchain.","attributes":',
                    entropy == bytes32(0) ? '[{"trait_type":"Status","value":"Unrevealed"}]' : _format(_getAttributes(seed)),
                    ',"image":"data:image/svg+xml;base64,' ,
                    bytes(_image(id, entropy, seed)).encode(),
                    '","animation_url":"data:text/html;base64,',
                    entropy == bytes32(0) ? _prerevealAnimation() : dataContract.encode(seed),
                    '"}'
                )
            ).encode()
        );
    }

    /**
     * @dev Get a quasirandom dataURI containing an html document with web audio
     *      code for playing a generative song and animation.
     */
    function explore() external view returns (string memory) {
        // Construct and return metadata using entropy from the previous block.
        return _explore(bytes32(block.prevrandao));
    }

    /**
     * @dev Get a dataURI containing an html document with web audio code for
     *      playing a specific generative instance of an audiovisual work using
     *      a deterministic seed, regardless of whether a token with the given
     *      seed exists.
     *
     * @param seed The seed to use for generating the audiovisual work.
     *
     * @return The dataURI containing the base64-encoded html audiovisuals.
     */
    function explore(bytes32 seed) external view returns (string memory) {
        // Construct and return the metadata using the supplied seed.
        return _explore(seed);
    }

    /**
     * @dev Get the name of this contract.
     */
    function name() public pure override returns (string memory) {
        // Return the name of this contract.
        return unicode"Ret↵rn";
    }

    /**
     * @dev Get the symbol of this contract.
     */
    function symbol() public pure override returns (string memory) {
        // Return the symbol of this contract.
        return unicode"↵";
    }

    /**
     * @dev Deconstruct the supplied seed into its constituent attributes,
     *      represented as strings.
     *
     * @param seed The provided seed.
     *
     * @return tempo
     * @return vibe
     * @return root
     * @return style
     * @return arrow
     * @return color
     * @return tone
     * @return creator The address of the account that minted the token.
     */
    function germinate(bytes32 seed) public pure returns (
        string memory tempo,
        string memory vibe,
        string memory root,
        string memory style,
        string memory arrow,
        string memory color,
        string memory tone,
        string memory creator
    ) {
        // Derive the attributes from the seed.
        Attributes memory attributes = _getAttributes(seed);

        // Return the attributes as distinct strings.
        return (
            attributes.tempo,
            attributes.vibe,
            attributes.root,
            attributes.style,
            attributes.arrow,
            attributes.color,
            attributes.tone,
            attributes.creator
        );
    }

    /**
     * @dev Get contract-level information, formatted as a dataURI containing a
     *      JSON object with the contract name, author, description, and
     *      collection image.
     */
    function contractURI() external view returns (string memory) {
        return string.concat(
            'data:application/json;base64,',
            Base64.encode(
                abi.encodePacked('{',
                    unicode'"name": "Ret↵rn", ',
                    '"author": "0age", ',
                    '"description": "Generative audiovisual art where all metadata is stored and rendered onchain. Each musical work is minted in an unrevealed state over an open, 3 day window from deployment. After the mint phase ends, entropy is sourced from both a future block and from a message whose contents are committed to at the time of deployment. This entropy is used to finalize metadata and reveal the end state of each minted work. Provenance is established for each token by permanently recording the account used to create it and incorporating the address into the seed that determines token attributes. Warning: flashing imagery & audio present.", ',
                    '"image": "data:image/svg+xml;base64,', bytes(_image(0, bytes32(0), bytes32(0))).encode(),
                '"}')
            )
        );
    }

    /**
     * @dev Internal function for minting a specified amount of tokens to a
     *      specified address. Ξ0.05 must be provided for each token minted, and
     *      minting is only possible during the mint phase, which lasts for 3
     *      days after deployment. As part of token creation, the address of the
     *      caller will be recorded as the creator of the tokens, and will be
     *      incorporated into each token's seed once reveal has been finalized.
     *
     * @param owner The address to mint the tokens to.
     * @param amount The amount of tokens to mint.
     */
    function _create(address owner, uint256 amount) internal {
        // Ensure that the mint phase is still active.
        if (mintComplete <= block.timestamp) {
            revert MintCompleted();
        }

        // Ensure that the correct amount of Ξ has been provided.
        if (msg.value != amount * 1 ether / 20) {
            revert InvalidMintValue();
        }

        // Determine the next token id to be minted, used to register creator.
        uint256 id = _nextTokenId();

        // Mint the tokens to the specified address.
        _mint(owner, amount);

        // Record the creator of the tokens.
        _creators[id] = msg.sender;
    }

    /**
     * @dev Internal function for burning a token. If the mint phase has been
     *      over for 30 minutes and the reveal phase has not been finalized, the
     *      owner of the token will be refunded Ξ0.05. Otherwise, the token will
     *      just be burned. Note that only the owner or an approved account can
     *      burn a token.
     *
     * @param id The id of the token to burn.
     *
     * @return A boolean representing whether or not the owner was refunded.
     */
    function _destroy(uint256 id) internal returns (bool) {
        // Determine the current owner of the token.
        address owner = ownerOf(id);

        // Burn the token if the owner is the caller or the caller is approved.
        _burn(id, true);

        // Declare a boolean representing whether or not the owner was refunded.
        bool refunded;

        // Refund if mint has been over for 30 minutes & global seed is not set.
        if (
            mintComplete + 30 minutes <= block.timestamp &&
            globalSeed == bytes32(0)
        ) {
            // Send the owner Ξ0.05 (the original mint amount per token).
            (bool ok, ) = owner.call{value: 1 ether / 20}("");

            // If the transfer fails, revert the transaction.
            if (!ok) {
                // Use assembly to "bubble up" return data if available and not
                // excessively long.
                assembly {
                    if and(returndatasize(), lt(returndatasize(), 0xffffff)) {
                        returndatacopy(0, 0, returndatasize())
                        revert(0, returndatasize())
                    }
                }

                // Otherwise, revert with a generic error.
                revert BurnRefundFailed();
            }

            // Mark the owner as having been refunded.
            refunded = true;
        } else {
            // Otherwise, mark the owner as not having been refunded.
            refunded = false;
        }

        // Return whether or not the owner was refunded.
        return refunded;
    }

    /**
     * @dev Internal function for deriving the seed of a token from its id, the
     *      global seed or other entropy source, and the creator of the token.
     *
     * @param id The id of the token to derive the seed for.
     * @param entropy The global seed or other entropy used to derive the seed.
     *
     * @return The derived seed.
     */
    function _getSeed(
        uint256 id,
        bytes32 entropy
    ) internal view returns (bytes32) {
        // Return seed using id, entropy, & token creator as determinants.
        return (
            keccak256(
                abi.encodePacked(id, entropy)
            ) & ~bytes32(uint256(type(uint160).max))
        ) | bytes32(uint256(uint160(_getCreator(id))));
    }

    /**
     * @dev Internal function for rendering pre-reveal animation, a countdown to
     *      the reveal that is displayed before the token's global seed has been
     *      set. The countdown ends at the timestamp stored in mintComplete.
     *
     * @return An html document, base64-encoded, containing a countdown to mint
     *         completion or a message if the mint phase is over but the reveal
     *         phase has not been finalized.
     */
    function _prerevealAnimation() internal view returns (string memory) {
        // Construct and return the pre-reveal animation.
        return bytes(
            string.concat(
                '<!doctypehtml><title>Ret&#8629;rn</title><meta content=0age name=author><style>body{background-color:#000;color:#d3d3d3;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;font-family:Arial,sans-serif;text-align:center}</style><div><h1 id=1></h1><h1 id=2></h1></div><script>let t=new Date(',
                mintComplete.toString(),
                'e3),m="Waiting for reveal...";let c;function u(){let e=new Date,n=t-e;n<=0?(clearInterval(c),document.getElementById("1").textContent=m,document.getElementById("2").style.display="none"):document.getElementById("2").textContent=[Math.floor(n/864e5),Math.floor(n%864e5/36e5),Math.floor(n%36e5/6e4),Math.floor(n%6e4/1e3)].map(e=>e.toString().padStart(2,"0")).join(":")}new Date<t?(document.getElementById("1").textContent="Waiting for mint to complete",u(),c=setInterval(u,1e3)):document.getElementById("1").textContent=m;</script>'
            )
        ).encode();
    }

    /**
     * @dev Internal view function for retrieving the address of the account
     *      that minted a specified token. Note that this function can consume
     *      a significant amount of gas in cases where the creator minted many
     *      tokens at once. Note that this function assumes that the supplied
     *      id has been confirmed to exist; otherwise, non-existent tokens will
     *      be treated as having been created by the most recent creator.
     *
     * @param id The id of the token in question.
     *
     * @return creator The address of the account that minted the token.
     */
    function _getCreator(uint256 id) internal view returns (address creator) {
        // Iterate until a creator has been located.
        while (true) {
            // Retrieve the creator of the token with the current id.
            creator = _creators[id];

            // If the retrieved address is not empty, return it.
            if (creator != address(0)) {
                return creator;
            }

            // Otherwise, decrement the id and try again.
            id -= 1;
        }
    }

    /**
     * @dev Internal view function for ensuring that the caller is the account
     *      currently resolved by the ENS name hash of contract author If the.
     *      caller is not the author, the transaction will revert.
     *
     * @return The account resolved by the author's ENS name hash.
     */
    function _onlyAuthor() internal view returns (address payable) {
        // Retrieve the address resolved by the author's ENS name hash.
        address authorAccount = author();

        // Revert if caller is not the address resolved by author's name hash.
        if (msg.sender != authorAccount) {
            revert Unauthorized();
        }

        // Return the author's account.
        return payable(authorAccount);
    }

    /**
     * @dev Internal function for deriving and rendering an SVG image for a token.
     *      If metadata is not yet revealed, default values are used. Otherwise, it
     *      is derived using the id and the global seed and returned as a string.
     *
     * @param id      The id of the token.
     * @param entropy The global seed value if one has been set via metadata reveal.
     * @param seed    The seed for the token if one has already been derived. If not
     *                provided, it will be derived using the id and the global seed.
     *
     * @return A string representing the SVG image for the token.
     */
    function _image(
        uint256 id,
        bytes32 entropy,
        bytes32 seed
    ) internal view returns (string memory) {
        // Declare variables representing visual properties of the token.
        string memory arrow;
        string memory color;
        bool vivid;

        // If metadata has not been revealed, use default values.
        if (entropy == bytes32(0)) {
            arrow = unicode"↵";
            color = "#000000";
            vivid = false;
        } else {
            // If a seed has not been provided, derive one using id and entropy.
            if (seed == bytes32(0)) {
                seed = _getSeed(id, entropy);
            }

            // Derive the visual properties of the token using the seed.
            (,,,, arrow, color,,) = germinate(seed);
            vivid = uint8(seed[10]) > 252;
        }

        // Render & return the SVG image for the token using derived properties.
        return _renderImage(arrow, color, vivid);
    }

    /**
     * @dev Internal view function for rendering a dataURI containing an html
     *      document with web audio code for playing a specific generative
     *      instance of an audiovisual work using a deterministic seed. Metadata
     *      is retrieved from a corresponding data contract and the seed is
     *      inserted into the code before it is base64-encoded and returned as a
     *      string.
     *
     * @param seed The seed to use for generating the audiovisual work.
     *
     * @return The dataURI containing the base64-encoded html audiovisuals.
     */
    function _explore(bytes32 seed) internal view returns (string memory) {
        return string.concat(
            "data:text/html;base64,",
            dataContract.encode(seed)
        );
    }

    /**
     * @dev Internal pure function for rendering an SVG image for a token using
     *      the provided visual properties.
     *
     * @return The SVG image as a string.
     */
    function _renderImage(
        string memory arrow,
        string memory color,
        bool vivid
    ) internal pure returns (string memory) {
        return string.concat('<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" fill="', color, '" /><text x="50" y="67" font-size="49" text-anchor="middle" fill="', vivid ? 'white' : 'lightgray', '" font-family="Arial">', arrow, '</text></svg>');
    }

    /**
     * @dev Internal pure function for rendering an array of attributes as a
     *      JSON string.
     *
     * @param attributes The attributes to format.
     *
     * @return The attributes formatted as a string.
     */
    function _format(
        Attributes memory attributes
    ) internal pure returns (string memory) {
        // Declare variables for storing the two halves of the JSON string.
        // This is necessary due to constraints on stack pressure.
        string memory a;
        string memory b;

        // Render the first half of the JSON string.
        {
            a = string.concat(
                '[{"trait_type":"Seed","value":"',
                attributes.seed,
                '"},{"trait_type":"Tempo","value":"',
                attributes.tempo,
                '"},{"trait_type":"Vibe","value":"',
                attributes.vibe,
                '"},{"trait_type":"Root","value":"',
                attributes.root,
                '"},{"trait_type":"Style","value":"',
                attributes.style
            );
        }

        // Render the second half of the JSON string.
        {
            b = string.concat(
                '"},{"trait_type":"Arrow","value":"',
                attributes.arrow,
                '"},{"trait_type":"Color","value":"',
                attributes.color,
                '"},{"trait_type":"Tone","value":"',
                attributes.tone,
                '"},{"trait_type":"Creator","value":"',
                attributes.creator
            );
        }

        // Concatenate the two halves and return the result.
        return string.concat(a, b, '"}]');
    }

    /**
     * @dev Internal pure function for deconstructing a supplied seed into
     *      its constituent attributes, represented by an Attributes struct.
     *
     * @param seed The provided seed.
     *
     * @return attributes The attributes represented by the seed.
     */
    function _getAttributes(
        bytes32 seed
    ) internal pure returns (
        Attributes memory attributes
    ) {
        // Encode the seed as a hex string and store it as the seed attribute.
        attributes.seed = uint256(seed).toHexString(32);

        // Derive the tempo attribute from the seed.
        attributes.tempo = (
            (uint256(uint8(seed[0])) + 192) % 128 + 64
        ).toString();

        // Derive the vibe attribute from the seed.
        attributes.vibe = ["2", "3", "4", "6"][uint8(seed[1]) >> 6];

        // Derive the root attribute from the seed.
        attributes.root = [
            unicode"E₁",
            unicode"F₁",
            unicode"F♯₁/G♭₁",
            unicode"G₁",
            unicode"G♯₁/A♭₁",
            unicode"A₁",
            unicode"A♯₁/B♭₁",
            unicode"B₁",
            unicode"C₂",
            unicode"C♯₂/D♭₂",
            unicode"D₂",
            unicode"D♯₂/E♭₂",
            unicode"E₂",
            unicode"F₂",
            unicode"F♯₂/G♭₂",
            unicode"G₂"
        ][uint8(seed[2]) >> 4];

        // Derive the style attribute from the seed.
        attributes.style = (uint8(seed[11]) & 0x0f) == 15
            ? "16"
            : (uint256(uint8(seed[7])) >> 4).toString();

        // Derive the arrow attribute from the seed.
        attributes.arrow = [
            unicode"↵",
            unicode"↙",
            unicode"↵",
            unicode"↜",
            unicode"↩",
            unicode"↵",
            unicode"⇇",
            unicode"⇐",
            unicode"↵",
            unicode"⇤",
            unicode"⇦",
            unicode"↵",
            unicode"⏎",
            unicode"↵",
            unicode"◀",
            unicode"⤶"
        ][uint8(seed[8]) >> 4];

        // Derive the color attribute from the seed.
        attributes.tone = uint256(
            (uint8(seed[10]) % 16 == 0) && (uint8(seed[11]) >> 4 < 4)
                ? uint8(seed[11]) >> 4
                : 0
        ).toString();

        // Derive the color attribute from the seed.
        uint8 startingColorKey = uint8(seed[10]);
        if (startingColorKey < 189) {
            attributes.color = "#000000";
        } else if (startingColorKey < 205) {
            attributes.color = "#ffffff";
        } else if (startingColorKey < 221) {
            attributes.color = "#ff0000";
        } else if (startingColorKey < 237) {
            attributes.color = "#00ff00";
        } else if (startingColorKey < 253) {
            attributes.color = "#0000ff";
        } else if (startingColorKey < 254) {
            attributes.color = "#ffff00";
        } else if (startingColorKey < 255) {
            attributes.color = "#ff00ff";
        } else {
            attributes.color = "#00ffff";
        }

        // Derive the creator attribute from the seed.
        attributes.creator = address(uint160(uint256(seed))).toHexString();

        // Return the derived attributes.
        return attributes;
    }
}